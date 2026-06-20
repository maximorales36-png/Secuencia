#!/usr/bin/env python3
"""
SECUENCIA v2 - Detector con clasificacion de forma geometrica
Detecta piezas 3D de colores por HSV + forma + tamaño real + persistencia temporal.

Nuevo pipeline:
  HSV -> mascara -> contornos -> area min/max
  -> CLASIFICAR FORMA (triangulo/cuadrado/circulo/hexagono)
  -> VERIFICAR TAMAÑO (con px_per_mm calibrado)
  -> PERSISTENCIA TEMPORAL (N frames consecutivos)
  -> centroide -> JSON (mismo formato que v1)

Uso:
  python secuencia_detector_ipc_v2.py [indice_camara] [--calibrate] [--calibrate-colors]
"""

import cv2
import numpy as np
import json
import time
import sys
import os
import tempfile
import shutil
import math

CAPTURE_WIDTH = 640
CAPTURE_HEIGHT = 400
CAMERA_INDEX = 0
CAMERA_AUTO_DETECT = True
CAMERA_BACKEND = cv2.CAP_DSHOW
SEND_FREQUENCY = 10
SEND_INTERVAL = 1.0 / SEND_FREQUENCY
MIN_CONTOUR_AREA = 400
MAX_CONTOUR_AREA = 50000

# --- NUEVOS PARAMETROS v2 ---

SHAPE_DETECTION_ENABLED = True
CLASSIFY_EPSILON = 0.05
CIRCULARITY_THRESHOLD = 0.80
SOLIDITY_THRESHOLD = 0.85
SIZE_TOLERANCE = 0.80
PX_PER_MM = None
MIN_CONSECUTIVE_FRAMES = 3
DETECTION_MEMORY_TIMEOUT = 0.5
DETECTION_STABILIZE_SNAP = 0.02
SHAPE_MATCH_PERMISSIVE = True

COLOR_SHAPE_MAP = {
    "pink":       {"shape": "polygon",  "size_mm": 55},   # Cubo
    "yellow":     {"shape": "polygon",  "size_mm": 65},   # Piramide
    "celeste":    {"shape": "hexagon",  "size_mm": 54},   # Hexagono (ancho total ~54mm)
    "neon_green": {"shape": "circle",   "size_mm": 55},   # Semiesfera
    "violet":     {"shape": "circle",   "size_mm": 65},   # Cono
    "orange":     {"shape": "unknown",  "size_mm": 0},    # Sin figura
}

# --- FIN NUEVOS PARAMETROS ---

IPC_DIR = tempfile.gettempdir()
IPC_FILE = os.path.join(IPC_DIR, "secuencia_pieces.json")
IPC_TEMP_FILE = os.path.join(IPC_DIR, "secuencia_pieces.tmp")

_script_dir = os.path.dirname(os.path.abspath(__file__))
CROP_CONFIG_FILE = os.path.join(_script_dir, "crop_config.json")
COLOR_CONFIG_FILE = os.path.join(_script_dir, "color_config.json")

CORNERS_ORDER = ["tl", "tr", "br", "bl"]
CORNERS_LABELS = ["TL", "TR", "BR", "BL"]

RECTIFIED_WIDTH = 640
RECTIFIED_HEIGHT = 480

COLOR_RANGES = {
    "yellow": {
        "lower": np.array([15, 80, 80]),
        "upper": np.array([35, 255, 255]),
        "bgr": (0, 255, 255)
    },
    "pink": {
        "lower": np.array([140, 50, 50]),
        "upper": np.array([180, 255, 255]),
        "bgr": (255, 192, 203)
    },
    "neon_green": {
        "lower": np.array([35, 100, 100]),
        "upper": np.array([85, 255, 255]),
        "bgr": (0, 255, 127)
    },
    "celeste": {
        "lower": np.array([95, 60, 150]),
        "upper": np.array([115, 255, 255]),
        "bgr": (246, 209, 81)
    },
    "violet": {
        "lower": np.array([120, 40, 40]),
        "upper": np.array([139, 255, 255]),
        "bgr": (255, 0, 255)
    }
}

CORNERS_OVERLAY_COLORS = [(0, 255, 255), (255, 0, 0), (0, 0, 255), (0, 255, 0)]


def classify_shape(contour):
    """
    Clasifica un contorno segun su forma, tolerante a deformacion
    por perspectiva. Retorna 'polygon', 'hexagon', 'circle' o 'unknown'.

    El filtro principal es SOLIDITY (compacidad):
      - Pieza fisica -> contorno compacto -> solidity > 0.85
      - Luz proyectada -> contorno irregular -> solidity bajo
    """
    peri = cv2.arcLength(contour, True)
    if peri <= 0:
        return "unknown"
    area = cv2.contourArea(contour)
    if area <= 0:
        return "unknown"

    hull = cv2.convexHull(contour)
    hull_area = cv2.contourArea(hull)
    solidity = area / hull_area if hull_area > 0 else 0
    if solidity < SOLIDITY_THRESHOLD:
        return "unknown"

    approx = cv2.approxPolyDP(contour, CLASSIFY_EPSILON * peri, True)
    vertices = len(approx)
    circularity = 4.0 * math.pi * area / (peri * peri) if peri > 0 else 0

    if circularity > CIRCULARITY_THRESHOLD:
        return "circle"

    if vertices <= 10:
        return "polygon"

    if circularity > 0.70:
        return "circle"

    return "polygon"


def create_roi_mask(frame_shape, corners_px):
    mask = np.zeros(frame_shape[:2], dtype=np.uint8)
    pts = np.array(corners_px, np.int32)
    cv2.fillPoly(mask, [pts], 255)
    return mask


def verify_size_raw(contour, color_name, M):
    """
    Verifica tamaño de la pieza transformando el bounding box del contorno
    (en RAW) al espacio rectificado a traves de la homografia M.
    Retorna True si pasa el filtro.
    """
    if not SHAPE_DETECTION_ENABLED:
        return True
    expected = COLOR_SHAPE_MAP.get(color_name)
    if expected is None or expected["shape"] == "unknown" or expected["size_mm"] <= 0:
        return True
    if PX_PER_MM is None or PX_PER_MM <= 0:
        return True

    x, y, w, h = cv2.boundingRect(contour)
    pts = np.array([[x, y], [x+w, y], [x+w, y+h], [x, y+h]], dtype=np.float32)
    warped_pts = cv2.perspectiveTransform(pts.reshape(-1, 1, 2), M)
    wr = cv2.boundingRect(warped_pts)
    warped_size = max(wr[2], wr[3])

    expected_px = expected["size_mm"] * PX_PER_MM
    lower = expected_px * (1.0 - SIZE_TOLERANCE)
    upper = expected_px * (1.0 + SIZE_TOLERANCE)
    return lower <= warped_size <= upper


def update_detection_memory(raw_detections, memory, now):
    """
    Filtra detecciones por persistencia temporal.
    memory: dict key = "color_snappedX" -> {color, x, y, consecutive, last_seen, matched}
    Retorna dict de detecciones confirmadas: {color: [(cx, cy)]}
    """
    for key in memory:
        memory[key]["matched"] = False

    for color_name, centers in raw_detections.items():
        for cx, cy, _ in centers:
            snapped_x = round(cx / RECTIFIED_WIDTH, 2)
            key = f"{color_name}_{snapped_x}"

            if key in memory:
                mem = memory[key]
                mem["x"] = int(mem["x"] * 0.7 + cx * 0.3)
                mem["y"] = int(mem["y"] * 0.7 + cy * 0.3)
                mem["consecutive"] += 1
                mem["last_seen"] = now
                mem["matched"] = True
            else:
                memory[key] = {
                    "color": color_name,
                    "x": cx,
                    "y": cy,
                    "consecutive": 1,
                    "last_seen": now,
                    "matched": True
                }

    expired = []
    for key, mem in memory.items():
        if now - mem["last_seen"] > DETECTION_MEMORY_TIMEOUT:
            expired.append(key)
    for key in expired:
        del memory[key]

    confirmed = {}
    for key, mem in memory.items():
        if mem["consecutive"] >= MIN_CONSECUTIVE_FRAMES:
            c = mem["color"]
            if c not in confirmed:
                confirmed[c] = []
            confirmed[c].append((mem["x"], mem["y"]))

    return confirmed


# --- FUNCIONES ORIGINALES (con adaptaciones v2) ---

def load_crop_config():
    global PX_PER_MM
    if not os.path.exists(CROP_CONFIG_FILE):
        return None
    try:
        with open(CROP_CONFIG_FILE, 'r') as f:
            config = json.load(f)
        if all(k in config for k in ("x", "y", "w", "h")):
            print(f"[Crop] Formato antiguo detectado. Eliminando...", file=sys.stderr)
            os.remove(CROP_CONFIG_FILE)
            return None
        if "corners" not in config or len(config["corners"]) != 4:
            print(f"[Crop] Config invalida (se requieren 4 esquinas)", file=sys.stderr)
            os.remove(CROP_CONFIG_FILE)
            return None
        corners = []
        for c in config["corners"]:
            if not all(k in c for k in ("x", "y")):
                raise ValueError("Formato de esquina invalido")
            corners.append((float(c["x"]), float(c["y"])))

        if "screen_width_mm" in config and config["screen_width_mm"] > 0:
            PX_PER_MM = RECTIFIED_WIDTH / config["screen_width_mm"]
            print(f"[Crop] px_per_mm = {PX_PER_MM:.4f} (screen_width={config['screen_width_mm']}mm)", file=sys.stderr)

        return corners
    except (json.JSONDecodeError, IOError, ValueError) as e:
        print(f"[Crop] Error leyendo config: {e}", file=sys.stderr)
        try:
            os.remove(CROP_CONFIG_FILE)
        except OSError:
            pass
        return None


def save_crop_config(corners_frac, screen_width_mm=None):
    config = {
        "order": CORNERS_ORDER,
        "corners": [{"x": round(x, 4), "y": round(y, 4)} for (x, y) in corners_frac]
    }
    if screen_width_mm is not None and screen_width_mm > 0:
        config["screen_width_mm"] = screen_width_mm
    tmp = CROP_CONFIG_FILE + ".tmp"
    with open(tmp, 'w') as f:
        json.dump(config, f, indent=2)
        f.flush()
        os.fsync(f.fileno())
    shutil.move(tmp, CROP_CONFIG_FILE)
    print(f"[Crop] Esquinas guardadas: {CROP_CONFIG_FILE}", file=sys.stderr)
    for i, label in enumerate(CORNERS_LABELS):
        x, y = corners_frac[i]
        print(f"[Crop]   {label}: ({x:.3f}, {y:.3f})", file=sys.stderr)
    if screen_width_mm is not None:
        print(f"[Crop]   Ancho pantalla: {screen_width_mm}mm", file=sys.stderr)


def corners_to_pixels(corners_frac, frame_w, frame_h):
    return [(int(round(x * frame_w)), int(round(y * frame_h))) for (x, y) in corners_frac]


def save_color_config(color_ranges):
    config = {}
    for color_name, range_data in color_ranges.items():
        config[color_name] = {
            "lower": [int(v) for v in range_data["lower"]],
            "upper": [int(v) for v in range_data["upper"]],
            "bgr": [int(v) for v in range_data["bgr"]]
        }
    tmp = COLOR_CONFIG_FILE + ".tmp"
    with open(tmp, 'w') as f:
        json.dump(config, f, indent=2)
        f.flush()
        os.fsync(f.fileno())
    shutil.move(tmp, COLOR_CONFIG_FILE)
    print(f"[Color] Rangos guardados: {COLOR_CONFIG_FILE}", file=sys.stderr)


def load_color_config():
    if not os.path.exists(COLOR_CONFIG_FILE):
        return None
    try:
        with open(COLOR_CONFIG_FILE, 'r') as f:
            config = json.load(f)
        expected = list(COLOR_RANGES.keys())
        result = {}
        for color_name in expected:
            if color_name not in config:
                print(f"[Color] '{color_name}' no encontrado en config", file=sys.stderr)
                return None
            c = config[color_name]
            if not all(k in c for k in ("lower", "upper", "bgr")):
                print(f"[Color] '{color_name}' formato invalido", file=sys.stderr)
                return None
            if len(c["lower"]) != 3 or len(c["upper"]) != 3 or len(c["bgr"]) != 3:
                print(f"[Color] '{color_name}' dimensiones incorrectas", file=sys.stderr)
                return None
            result[color_name] = {
                "lower": np.array(c["lower"], dtype=np.uint8),
                "upper": np.array(c["upper"], dtype=np.uint8),
                "bgr": tuple(c["bgr"])
            }
        print(f"[Color] Rangos cargados: {COLOR_CONFIG_FILE}", file=sys.stderr)
        return result
    except (json.JSONDecodeError, IOError, ValueError) as e:
        print(f"[Color] Error leyendo config: {e}", file=sys.stderr)
        return None


def apply_perspective_crop(frame, corners_frac, out_w, out_h):
    h, w = frame.shape[:2]
    src_pts = np.array([[x * w, y * h] for (x, y) in corners_frac], dtype=np.float32)
    dst_pts = np.array([[0, 0], [out_w, 0], [out_w, out_h], [0, out_h]], dtype=np.float32)
    M = cv2.getPerspectiveTransform(src_pts, dst_pts)
    warped = cv2.warpPerspective(frame, M, (out_w, out_h))
    return warped, M


def draw_corners_overlay(frame, corners_px):
    if not corners_px:
        return frame.copy()

    h, w = frame.shape[:2]
    pts = np.array(corners_px, np.int32)
    result = frame.copy()

    if len(corners_px) >= 3:
        mask = np.zeros((h, w), dtype=np.uint8)
        cv2.fillPoly(mask, [pts], 255)
        overlay = frame.copy()
        overlay[mask == 0] = (overlay[mask == 0] * 0.35).astype(np.uint8)
        result = cv2.addWeighted(overlay, 0.65, frame, 0.35, 0)

    if len(corners_px) >= 2:
        cv2.polylines(result, [pts], len(corners_px) == 4, (0, 255, 0), 2)

    for i, (cx, cy) in enumerate(corners_px):
        color = CORNERS_OVERLAY_COLORS[i]
        cv2.circle(result, (cx, cy), 8, color, -1)
        cv2.circle(result, (cx, cy), 8, (255, 255, 255), 2)
        cv2.putText(result, CORNERS_LABELS[i], (cx + 12, cy + 6),
                   cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)
        cv2.putText(result, f"{i+1}", (cx - 4, cy + 4),
                   cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)

    return result


def detect_color(frame, color_name, color_range, M_persp=None, region_mask=None):
    """
    Detecta un color en el frame RAW y filtra por forma + tamaño.
    region_mask: mascara poligonal para limitar el area de busqueda.
    M_persp: matriz de homografia raw->warped para verify_size_raw().
    Retorna lista de (cx, cy, shape_name) en coordenadas RAW.
    """
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    lower = color_range["lower"]
    upper = color_range["upper"]
    mask = cv2.inRange(hsv, lower, upper)
    if region_mask is not None:
        mask = cv2.bitwise_and(mask, region_mask)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    centers = []
    for contour in contours:
        area = cv2.contourArea(contour)
        if area <= MIN_CONTOUR_AREA or area >= MAX_CONTOUR_AREA:
            continue

        shape_name = classify_shape(contour) if SHAPE_DETECTION_ENABLED else "unknown"
        if SHAPE_DETECTION_ENABLED and shape_name == "unknown":
            continue

        if SHAPE_DETECTION_ENABLED and SHAPE_MATCH_PERMISSIVE:
            expected = COLOR_SHAPE_MAP.get(color_name, {}).get("shape", "unknown")
            if expected != "unknown" and expected != shape_name:
                if expected == "circle" and shape_name != "circle":
                    continue
                if expected == "polygon" and shape_name == "circle":
                    continue
                if expected == "hexagon" and shape_name == "circle":
                    continue

        if M_persp is not None and not verify_size_raw(contour, color_name, M_persp):
            continue

        Mo = cv2.moments(contour)
        if Mo["m00"] > 0:
            cx = int(Mo["m10"] / Mo["m00"])
            cy = int(Mo["m01"] / Mo["m00"])
            centers.append((cx, cy, shape_name))
    return centers


def draw_detections(frame, detections):
    for color_name, centers in detections.items():
        color_bgr = COLOR_RANGES[color_name]["bgr"]
        for item in centers:
            cx = item[0]
            cy = item[1]
            shape_name = item[2] if len(item) > 2 else ""
            cv2.circle(frame, (cx, cy), 8, color_bgr, -1)
            cv2.circle(frame, (cx, cy), 10, (255, 255, 255), 1)
            label = f"{color_name}"
            if shape_name and shape_name != "unknown":
                label = f"{shape_name} {color_name}"
            cv2.putText(frame, label, (cx + 12, cy - 10),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.4, color_bgr, 1)


def format_data(detections, frame_w, frame_h):
    data = {"piezas": []}
    for color_name, centers in detections.items():
        for entry in centers:
            cx, cy = entry[0], entry[1]
            data["piezas"].append({
                "color": color_name,
                "x": round(cx / frame_w, 3) if frame_w > 0 else 0,
                "y": round(cy / frame_h, 3) if frame_h > 0 else 0
            })
    return data


def send_data(data):
    json_str = json.dumps(data)
    with open(IPC_TEMP_FILE, 'w', encoding='utf-8') as f:
        f.write(json_str + '\n')
        f.flush()
        os.fsync(f.fileno())
    shutil.move(IPC_TEMP_FILE, IPC_FILE)
    print(json.dumps({"__info": len(data["piezas"])}), file=sys.stderr)


def find_camera():
    if not CAMERA_AUTO_DETECT:
        return CAMERA_INDEX
    for i in range(5):
        print(f"[Video] Probando camara en indice {i}...", file=sys.stderr, end=" ", flush=True)
        cap = cv2.VideoCapture(i, CAMERA_BACKEND)
        if cap.isOpened():
            cap.release()
            print(f"OK (indice {i})", file=sys.stderr)
            return i
        print("no disponible", file=sys.stderr)
    print("[Video] No se encontro camara, usando indice por defecto", file=sys.stderr)
    return CAMERA_INDEX


def calibrate_corners(cap):
    raw_corners = []
    window_name = "Calibracion - Marque 4 esquinas del TV"

    def mouse_handler(event, x, y, flags, param):
        nonlocal raw_corners
        if event == cv2.EVENT_LBUTTONDOWN and len(raw_corners) < 4:
            raw_corners.append((x, y))

    cv2.namedWindow(window_name)
    cv2.setMouseCallback(window_name, mouse_handler)

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        display = draw_corners_overlay(frame, raw_corners)

        if len(raw_corners) < 4:
            msg = f"Click en esquina {len(raw_corners) + 1}: {CORNERS_LABELS[len(raw_corners)]}"
            color = CORNERS_OVERLAY_COLORS[min(len(raw_corners), 3)]
            cv2.putText(display, msg, (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)
        else:
            cv2.putText(display, "[C] Confirmar  [R] Reset  [Q] Cancelar",
                       (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1)
            h_f, w_f = frame.shape[:2]
            corners_frac = [(x / w_f, y / h_f) for (x, y) in raw_corners]
            preview_h = 160
            preview_w = int(preview_h * RECTIFIED_WIDTH / RECTIFIED_HEIGHT)
            warped, _ = apply_perspective_crop(frame, corners_frac, preview_w, preview_h)
            preview_y = h_f - preview_h - 10
            preview_x = w_f - preview_w - 10
            display[preview_y:preview_y + preview_h, preview_x:preview_x + preview_w] = warped
            cv2.rectangle(display, (preview_x - 2, preview_y - 2),
                         (preview_x + preview_w + 2, preview_y + preview_h + 2),
                         (255, 255, 255), 1)
            cv2.putText(display, "Vista previa", (preview_x + 4, preview_y + 16),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.35, (255, 255, 255), 1)

        cv2.imshow(window_name, display)

        key = cv2.waitKey(30) & 0xFF
        if key == ord('c') or key == ord('C'):
            if len(raw_corners) == 4:
                break
        elif key == ord('r') or key == ord('R'):
            raw_corners = []
        elif key == ord('u') or key == ord('U'):
            if raw_corners:
                raw_corners.pop()
        elif key == ord('q') or key == ord('Q') or key == 27:
            cv2.destroyWindow(window_name)
            return None

    cv2.destroyWindow(window_name)

    if len(raw_corners) == 4:
        h_f, w_f = frame.shape[:2]
        corners_frac = [(x / w_f, y / h_f) for (x, y) in raw_corners]

        screen_width_mm = None
        try:
            inp = input(f"Ingrese el ancho REAL de la pantalla/TV en mm "
                        f"(enter para omitir, ej: 1200): ").strip()
            if inp:
                screen_width_mm = float(inp)
                if screen_width_mm > 0:
                    global PX_PER_MM
                    PX_PER_MM = RECTIFIED_WIDTH / screen_width_mm
                    print(f"[Crop] px_per_mm calibrado: {PX_PER_MM:.4f} "
                          f"({RECTIFIED_WIDTH}px / {screen_width_mm}mm)", file=sys.stderr)
        except (ValueError, EOFError):
            print("[Crop] Ancho no ingresado, se usara deteccion sin filtro de tamaño", file=sys.stderr)

        save_crop_config(corners_frac, screen_width_mm)
        return corners_frac
    return None


COLOR_NAMES_LIST = list(COLOR_RANGES.keys())


def calibrate_colors(cap, corners_frac, current_ranges):
    current_idx = 0
    working = {}
    for name, data in current_ranges.items():
        working[name] = {
            "lower": data["lower"].copy(),
            "upper": data["upper"].copy(),
            "bgr": data["bgr"]
        }

    defaults = {}
    for name, data in COLOR_RANGES.items():
        defaults[name] = {
            "lower": data["lower"].copy(),
            "upper": data["upper"].copy(),
            "bgr": data["bgr"]
        }

    window_name = "Cal HSV - [1-6] Color  [R] Reset  [S] Guardar  [Q] Salir"
    cv2.namedWindow(window_name)

    cv2.createTrackbar("H_Low", window_name, 0, 179, lambda x: None)
    cv2.createTrackbar("H_High", window_name, 179, 179, lambda x: None)
    cv2.createTrackbar("S_Low", window_name, 0, 255, lambda x: None)
    cv2.createTrackbar("S_High", window_name, 255, 255, lambda x: None)
    cv2.createTrackbar("V_Low", window_name, 0, 255, lambda x: None)
    cv2.createTrackbar("V_High", window_name, 255, 255, lambda x: None)

    def set_trackbars(color_name):
        lo = working[color_name]["lower"]
        hi = working[color_name]["upper"]
        cv2.setTrackbarPos("H_Low", window_name, int(lo[0]))
        cv2.setTrackbarPos("H_High", window_name, int(hi[0]))
        cv2.setTrackbarPos("S_Low", window_name, int(lo[1]))
        cv2.setTrackbarPos("S_High", window_name, int(hi[1]))
        cv2.setTrackbarPos("V_Low", window_name, int(lo[2]))
        cv2.setTrackbarPos("V_High", window_name, int(hi[2]))

    set_trackbars(COLOR_NAMES_LIST[current_idx])

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        warped, _ = apply_perspective_crop(frame, corners_frac,
                                           RECTIFIED_WIDTH, RECTIFIED_HEIGHT)

        color_name = COLOR_NAMES_LIST[current_idx]
        lo = working[color_name]["lower"]
        hi = working[color_name]["upper"]

        lo[0] = cv2.getTrackbarPos("H_Low", window_name)
        hi[0] = cv2.getTrackbarPos("H_High", window_name)
        lo[1] = cv2.getTrackbarPos("S_Low", window_name)
        hi[1] = cv2.getTrackbarPos("S_High", window_name)
        lo[2] = cv2.getTrackbarPos("V_Low", window_name)
        hi[2] = cv2.getTrackbarPos("V_High", window_name)

        for i in range(3):
            if lo[i] > hi[i]:
                lo[i], hi[i] = hi[i], lo[i]

        hsv = cv2.cvtColor(warped, cv2.COLOR_BGR2HSV)
        mask = cv2.inRange(hsv, lo, hi)
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)

        bgr = working[color_name]["bgr"]
        colored = np.zeros_like(warped)
        colored[mask > 0] = bgr
        display = cv2.addWeighted(warped, 0.6, colored, 0.4, 0)

        mask_small = cv2.resize(mask, (120, 90))
        mask_bgr = cv2.cvtColor(mask_small, cv2.COLOR_GRAY2BGR)
        h_disp, w_disp = display.shape[:2]
        ox, oy = w_disp - 130, h_disp - 100
        display[oy:oy + 90, ox:ox + 120] = mask_bgr
        cv2.rectangle(display, (ox - 1, oy - 1),
                     (ox + 121, oy + 91), (200, 200, 200), 1)

        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        for cnt in contours:
            area = cv2.contourArea(cnt)
            if MIN_CONTOUR_AREA < area < MAX_CONTOUR_AREA:
                cv2.drawContours(display, [cnt], 0, bgr, 2)
                Mo = cv2.moments(cnt)
                if Mo["m00"] > 0:
                    cx = int(Mo["m10"] / Mo["m00"])
                    cy = int(Mo["m01"] / Mo["m00"])
                    cv2.circle(display, (cx, cy), 4, bgr, -1)

        shape_text = ""
        expected_shape = COLOR_SHAPE_MAP.get(color_name, {}).get("shape", "unknown")
        if SHAPE_DETECTION_ENABLED and expected_shape != "unknown":
            shape_text = f"  esperado: {expected_shape}"

        cv2.putText(display, f"{color_name} [{current_idx + 1}/6]{shape_text}",
                    (10, 25), cv2.FONT_HERSHEY_SIMPLEX, 0.55, bgr, 2)
        cv2.putText(display,
                    f"H:{lo[0]:3d}-{hi[0]:3d}  S:{lo[1]:3d}-{hi[1]:3d}  V:{lo[2]:3d}-{hi[2]:3d}",
                    (10, 48), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (200, 200, 200), 1)
        cv2.putText(display, "[1-6] Color  [R] Reset  [S] Guardar  [Q] Salir",
                    (10, 72), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (120, 120, 120), 1)

        cv2.imshow(window_name, display)

        key = cv2.waitKey(30) & 0xFF

        if key == 27 or key == ord('q') or key == ord('Q'):
            cv2.destroyWindow(window_name)
            return None
        elif key == ord('s') or key == ord('S'):
            cv2.destroyWindow(window_name)
            return working
        elif key == ord('r') or key == ord('R'):
            working[color_name]["lower"] = defaults[color_name]["lower"].copy()
            working[color_name]["upper"] = defaults[color_name]["upper"].copy()
            set_trackbars(color_name)
        elif ord('1') <= key <= ord('6'):
            current_idx = key - ord('1')
            set_trackbars(COLOR_NAMES_LIST[current_idx])

    cv2.destroyWindow(window_name)
    return None


def print_usage():
    print(file=sys.stderr)
    print("Uso: python secuencia_detector_ipc_v2.py [indice_camara] [--calibrate] [--calibrate-colors]", file=sys.stderr)
    print(file=sys.stderr)
    print("  --calibrate         Forzar calibracion de esquinas (crop)", file=sys.stderr)
    print("  --calibrate-colors  Forzar calibracion de colores HSV", file=sys.stderr)
    print("  C: Re-calibrar esquinas   B: Calibrar colores HSV", file=sys.stderr)
    print("  V: Ver raw (camara sin rectificar)   Q: Salir", file=sys.stderr)
    print("  S: Alternar filtro de forma geometrica ON/OFF", file=sys.stderr)
    print(file=sys.stderr)


def main():
    global CAMERA_INDEX, SHAPE_DETECTION_ENABLED, PX_PER_MM

    calibrate_mode = False
    calibrate_colors_mode = False
    for arg in sys.argv[1:]:
        if arg == "--calibrate":
            calibrate_mode = True
        elif arg == "--calibrate-colors":
            calibrate_colors_mode = True
        elif arg == "--help" or arg == "-h":
            print_usage()
            return
        elif arg == "--no-shape":
            SHAPE_DETECTION_ENABLED = False
            print("[v2] Filtro de forma DESACTIVADO", file=sys.stderr)
        else:
            try:
                CAMERA_INDEX = int(arg)
                print(f"[Video] Indice de camara forzado a {CAMERA_INDEX}", file=sys.stderr)
            except ValueError:
                print(f"[Video] Ignorando argumento invalido: {arg}", file=sys.stderr)

    print("[SECUENCIA v2] Iniciando detector con clasificacion de forma", file=sys.stderr)
    print(f"Resolucion: {CAPTURE_WIDTH}x{CAPTURE_HEIGHT}", file=sys.stderr)
    print(f"Rectificado: {RECTIFIED_WIDTH}x{RECTIFIED_HEIGHT}", file=sys.stderr)
    print(f"IPC: {IPC_FILE}", file=sys.stderr)
    print(f"Frecuencia: {SEND_FREQUENCY} Hz", file=sys.stderr)
    print(f"Shape detection: {'ON' if SHAPE_DETECTION_ENABLED else 'OFF'}", file=sys.stderr)
    print(f"Persistencia temporal: {MIN_CONSECUTIVE_FRAMES} frames", file=sys.stderr)
    if PX_PER_MM:
        print(f"px_per_mm: {PX_PER_MM:.4f}", file=sys.stderr)
    else:
        print(f"px_per_mm: NO CALIBRADO (filtro de tamaño desactivado)", file=sys.stderr)
    print("-" * 60, file=sys.stderr)

    cam_idx = find_camera()
    cap = cv2.VideoCapture(cam_idx, CAMERA_BACKEND)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    if not cap.isOpened():
        print(f"[ERROR] No se pudo abrir la camara (indice {cam_idx}).", file=sys.stderr)
        return

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, CAPTURE_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAPTURE_HEIGHT)

    actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    if (actual_w, actual_h) != (CAPTURE_WIDTH, CAPTURE_HEIGHT):
        print(f"[Video] ATENCION: resolucion solicitada {CAPTURE_WIDTH}x{CAPTURE_HEIGHT} "
              f"pero la camara entrega {actual_w}x{actual_h}", file=sys.stderr)
    else:
        print(f"[Video] Resolucion confirmada: {actual_w}x{actual_h}", file=sys.stderr)

    corners_frac = load_crop_config()

    if calibrate_mode or corners_frac is None:
        if corners_frac is None:
            print("[Crop] No hay configuracion. Iniciando calibracion...", file=sys.stderr)
        result = calibrate_corners(cap)
        if result is not None:
            corners_frac = result
        elif corners_frac is None:
            print("[ERROR] No hay configuracion de esquinas. Saliendo.", file=sys.stderr)
            cap.release()
            return

    loaded_colors = load_color_config()
    if loaded_colors:
        COLOR_RANGES.clear()
        COLOR_RANGES.update(loaded_colors)

    if calibrate_colors_mode:
        print("[Color] Modo calibracion forzado por --calibrate-colors", file=sys.stderr)
        result = calibrate_colors(cap, corners_frac, COLOR_RANGES)
        if result is not None:
            COLOR_RANGES.clear()
            COLOR_RANGES.update(result)

    last_send_time = time.time()
    frame_count = 0
    running = True
    window_name = "SECUENCIA v2 - Detector"
    show_raw = False
    show_shape_debug = True

    detection_memory = {}
    prev_frame_size = None
    roi_mask = None
    corners_px = None

    try:
        while running:
            ret, frame = cap.read()
            if not ret:
                print("[ERROR] No se pudo leer frame.", file=sys.stderr)
                break

            h_f, w_f = frame.shape[:2]
            if prev_frame_size != (h_f, w_f) or roi_mask is None:
                corners_px = corners_to_pixels(corners_frac, w_f, h_f)
                roi_mask = create_roi_mask(frame.shape, corners_px)
                prev_frame_size = (h_f, w_f)

            warped, M = apply_perspective_crop(
                frame, corners_frac, RECTIFIED_WIDTH, RECTIFIED_HEIGHT
            )

            raw_detections = {}
            for color_name in COLOR_RANGES.keys():
                centers = detect_color(frame, color_name, COLOR_RANGES[color_name],
                                      M_persp=M, region_mask=roi_mask)
                if centers:
                    raw_detections[color_name] = centers

            warped_detections = {}
            for color_name, centers in raw_detections.items():
                warped_centers = []
                for cx, cy, shape_name in centers:
                    pt = np.array([[cx, cy]], dtype=np.float32).reshape(-1, 1, 2)
                    w_pt = cv2.perspectiveTransform(pt, M)
                    wx, wy = int(round(w_pt[0][0][0])), int(round(w_pt[0][0][1]))
                    warped_centers.append((wx, wy, shape_name))
                if warped_centers:
                    warped_detections[color_name] = warped_centers

            now = time.time()
            detections = update_detection_memory(warped_detections, detection_memory, now)

            if show_raw:
                display = draw_corners_overlay(frame, corners_px)
                preview_h = 160
                preview_w = int(preview_h * RECTIFIED_WIDTH / RECTIFIED_HEIGHT)
                warped_small = cv2.resize(warped, (preview_w, preview_h))
                preview_y = h_f - preview_h - 10
                preview_x = w_f - preview_w - 10
                display[preview_y:preview_y + preview_h, preview_x:preview_x + preview_w] = warped_small
                cv2.rectangle(display, (preview_x - 2, preview_y - 2),
                             (preview_x + preview_w + 2, preview_y + preview_h + 2),
                             (255, 255, 255), 1)
                draw_detections(display, detections)
            else:
                display = warped.copy()
                draw_detections(display, detections)

            total_pieces = sum(len(centers) for centers in detections.values())
            mode_label = "RAW" if show_raw else "RECTIFICADO"

            raw_count = sum(len(c) for c in raw_detections.values())
            mem_count = len(detection_memory)
            shape_status = "ON" if SHAPE_DETECTION_ENABLED else "OFF"

            cv2.putText(display, f"Frame: {frame_count} | {mode_label} | Shape:{shape_status}",
                       (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.50, (200, 200, 200), 1)
            cv2.putText(display, f"Piezas: {total_pieces} (raw:{raw_count} mem:{mem_count})",
                       (10, 55), cv2.FONT_HERSHEY_SIMPLEX, 0.50, (200, 200, 200), 1)

            if show_shape_debug and not show_raw:
                for color_name, centers in warped_detections.items():
                    for cx, cy, shape_name in centers:
                        cv2.putText(display, f"{shape_name}",
                                   (cx - 20, cy + 20), cv2.FONT_HERSHEY_SIMPLEX,
                                   0.35, (255, 255, 255), 1)

            cv2.imshow(window_name, display)

            current_time = time.time()
            if current_time - last_send_time >= SEND_INTERVAL:
                data = format_data(detections, RECTIFIED_WIDTH, RECTIFIED_HEIGHT)
                send_data(data)
                last_send_time = current_time

            frame_count += 1

            key = cv2.waitKey(1) & 0xFF
            if key == ord('q') or key == ord('Q'):
                print("\n[OK] Saliendo...", file=sys.stderr)
                running = False
                break
            elif key == ord('c') or key == ord('C'):
                print("\n[Crop] Re-calibrando esquinas...", file=sys.stderr)
                result = calibrate_corners(cap)
                if result is not None:
                    corners_frac = result
                    roi_mask = None
                    prev_frame_size = None
            elif key == ord('b') or key == ord('B'):
                print("\n[Color] Calibrando colores...", file=sys.stderr)
                result = calibrate_colors(cap, corners_frac, COLOR_RANGES)
                if result is not None:
                    COLOR_RANGES.clear()
                    COLOR_RANGES.update(result)
            elif key == ord('v') or key == ord('V'):
                show_raw = not show_raw
            elif key == ord('s') or key == ord('S'):
                SHAPE_DETECTION_ENABLED = not SHAPE_DETECTION_ENABLED
                print(f"\n[v2] Filtro de forma: {'ON' if SHAPE_DETECTION_ENABLED else 'OFF'}", file=sys.stderr)
            elif key == ord('d') or key == ord('D'):
                show_shape_debug = not show_shape_debug
                print(f"\n[v2] Debug de forma: {'ON' if show_shape_debug else 'OFF'}", file=sys.stderr)

    except KeyboardInterrupt:
        print("\n[OK] Interrumpido por usuario.", file=sys.stderr)
        running = False

    finally:
        cap.release()
        cv2.destroyAllWindows()
        if os.path.exists(IPC_FILE):
            os.remove(IPC_FILE)
        print("[OK] Recursos liberados.", file=sys.stderr)


if __name__ == "__main__":
    main()
