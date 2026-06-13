#!/usr/bin/env python3
"""
SECUENCIA - Detector de Postits (IPC por archivo)
Detecta postits de colores en tiempo real y escribe posiciones
a un archivo JSON compartido para que Godot lo lea.

Soporta correccion de perspectiva y calibracion interactiva de rangos HSV.

Uso:
  python secuencia_detector_ipc.py [indice_camara] [--calibrate] [--calibrate-colors]
"""

import cv2
import numpy as np
import json
import time
import sys
import os
import tempfile
import shutil

CAPTURE_WIDTH = 640
CAPTURE_HEIGHT = 480
CAMERA_INDEX = 0
CAMERA_AUTO_DETECT = True
CAMERA_BACKEND = cv2.CAP_DSHOW
SEND_FREQUENCY = 10
SEND_INTERVAL = 1.0 / SEND_FREQUENCY
MIN_CONTOUR_AREA = 400
MAX_CONTOUR_AREA = 50000

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
    "orange": {
        "lower": np.array([5, 100, 100]),
        "upper": np.array([15, 255, 255]),
        "bgr": (0, 165, 255)
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


def load_crop_config():
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
        return corners
    except (json.JSONDecodeError, IOError, ValueError) as e:
        print(f"[Crop] Error leyendo config: {e}", file=sys.stderr)
        try:
            os.remove(CROP_CONFIG_FILE)
        except OSError:
            pass
        return None


def save_crop_config(corners_frac):
    config = {
        "order": CORNERS_ORDER,
        "corners": [{"x": round(x, 4), "y": round(y, 4)} for (x, y) in corners_frac]
    }
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


def detect_color(frame, color_name, color_range):
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    lower = color_range["lower"]
    upper = color_range["upper"]
    mask = cv2.inRange(hsv, lower, upper)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    centers = []
    for contour in contours:
        area = cv2.contourArea(contour)
        if MIN_CONTOUR_AREA < area < MAX_CONTOUR_AREA:
            M = cv2.moments(contour)
            if M["m00"] > 0:
                cx = int(M["m10"] / M["m00"])
                cy = int(M["m01"] / M["m00"])
                centers.append((cx, cy, contour))
    return centers


def draw_detections(frame, detections):
    for color_name, centers in detections.items():
        color_bgr = COLOR_RANGES[color_name]["bgr"]
        for cx, cy, contour in centers:
            cv2.drawContours(frame, [contour], 0, color_bgr, 2)
            cv2.circle(frame, (cx, cy), 5, color_bgr, -1)
            cv2.putText(frame, color_name, (cx + 10, cy - 10),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.4, color_bgr, 1)


def format_data(detections, frame_w, frame_h):
    data = {"piezas": []}
    for color_name, centers in detections.items():
        for cx, cy, _ in centers:
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
            preview_size = 160
            warped, _ = apply_perspective_crop(frame, corners_frac, preview_size, preview_size)
            preview_y = h_f - preview_size - 10
            preview_x = w_f - preview_size - 10
            display[preview_y:preview_y + preview_size, preview_x:preview_x + preview_size] = warped
            cv2.rectangle(display, (preview_x - 2, preview_y - 2),
                         (preview_x + preview_size + 2, preview_y + preview_size + 2),
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
        corners_frac = [(x / CAPTURE_WIDTH, y / CAPTURE_HEIGHT) for (x, y) in raw_corners]
        save_crop_config(corners_frac)
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

        cv2.putText(display, f"{color_name} [{current_idx + 1}/6]",
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
    print("Uso: python secuencia_detector_ipc.py [indice_camara] [--calibrate] [--calibrate-colors]", file=sys.stderr)
    print(file=sys.stderr)
    print("  --calibrate         Forzar calibracion de esquinas (crop)", file=sys.stderr)
    print("  --calibrate-colors  Forzar calibracion de colores HSV", file=sys.stderr)
    print("  C: Re-calibrar esquinas   B: Calibrar colores HSV", file=sys.stderr)
    print("  V: Ver raw (camara sin rectificar)   Q: Salir", file=sys.stderr)
    print(file=sys.stderr)


def main():
    global CAMERA_INDEX

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
        else:
            try:
                CAMERA_INDEX = int(arg)
                print(f"[Video] Indice de camara forzado a {CAMERA_INDEX}", file=sys.stderr)
            except ValueError:
                print(f"[Video] Ignorando argumento invalido: {arg}", file=sys.stderr)

    print("[SECUENCIA] Iniciando detector (IPC por archivo)", file=sys.stderr)
    print(f"Resolucion: {CAPTURE_WIDTH}x{CAPTURE_HEIGHT}", file=sys.stderr)
    print(f"Rectificado: {RECTIFIED_WIDTH}x{RECTIFIED_HEIGHT}", file=sys.stderr)
    print(f"IPC: {IPC_FILE}", file=sys.stderr)
    print(f"Frecuencia: {SEND_FREQUENCY} Hz", file=sys.stderr)
    print("-" * 60, file=sys.stderr)

    cam_idx = find_camera()
    cap = cv2.VideoCapture(cam_idx, CAMERA_BACKEND)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    if not cap.isOpened():
        print(f"[ERROR] No se pudo abrir la camara (indice {cam_idx}).", file=sys.stderr)
        return

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, CAPTURE_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAPTURE_HEIGHT)

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
    window_name = "SECUENCIA - Detector (IPC)"
    show_raw = False

    try:
        while running:
            ret, frame = cap.read()
            if not ret:
                print("[ERROR] No se pudo leer frame.", file=sys.stderr)
                break

            warped, M = apply_perspective_crop(
                frame, corners_frac, RECTIFIED_WIDTH, RECTIFIED_HEIGHT
            )

            detections = {}
            for color_name in COLOR_RANGES.keys():
                detections[color_name] = detect_color(warped, color_name, COLOR_RANGES[color_name])

            if show_raw:
                h_f, w_f = frame.shape[:2]
                corners_px = corners_to_pixels(corners_frac, w_f, h_f)
                display = draw_corners_overlay(frame, corners_px)
                preview_size = 160
                warped_small = cv2.resize(warped, (preview_size, preview_size))
                preview_y = h_f - preview_size - 10
                preview_x = w_f - preview_size - 10
                display[preview_y:preview_y + preview_size, preview_x:preview_x + preview_size] = warped_small
                cv2.rectangle(display, (preview_x - 2, preview_y - 2),
                             (preview_x + preview_size + 2, preview_y + preview_size + 2),
                             (255, 255, 255), 1)
            else:
                display = warped.copy()
                draw_detections(display, detections)

            total_pieces = sum(len(centers) for centers in detections.values())
            mode_label = "RAW" if show_raw else "RECTIFICADO"
            cv2.putText(display, f"Frame: {frame_count} | {mode_label}", (10, 30),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.55, (200, 200, 200), 1)
            cv2.putText(display, f"Piezas: {total_pieces}", (10, 55),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.55, (200, 200, 200), 1)

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
            elif key == ord('b') or key == ord('B'):
                print("\n[Color] Calibrando colores...", file=sys.stderr)
                result = calibrate_colors(cap, corners_frac, COLOR_RANGES)
                if result is not None:
                    COLOR_RANGES.clear()
                    COLOR_RANGES.update(result)
            elif key == ord('v') or key == ord('V'):
                show_raw = not show_raw

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
