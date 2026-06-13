#!/usr/bin/env python3
"""
SECUENCIA - Detector de Postits (IPC por archivo)
Detecta postits de colores en tiempo real y escribe posiciones
a un archivo JSON compartido para que Godot lo lea.
Sin dependencia de red — funciona sin WiFi.

Soporta correccion de perspectiva: el usuario marca las 4 esquinas
del televisor y la imagen se rectifica para eliminar la angulacion
de la camara. Las coordenadas 0-1 se corresponden exactamente con
los bordes de la pantalla.

Incluye calibracion interactiva de rangos HSV por color con
trackbars en vivo y mascara superpuesta.

Uso:
  python secuencia_detector_ipc.py [indice_camara] [--calibrate] [--calibrate-colors]

  indice_camara       Numero de dispositivo de camara (0, 1, ...)
  --calibrate         Forzar calibracion de esquinas (crop)
  --calibrate-colors  Forzar calibracion de colores HSV

  Calibracion de esquinas (--calibrate o tecla C):
    Click: Marcar esquina (TL->TR->BR->BL)
    R: Resetear esquinas
    U: Deshacer ultima esquina
    C: Guardar y continuar
    Q: Cancelar

  Calibracion de colores (--calibrate-colors o tecla B):
    Trackbars: Ajustar H_Low/H_High, S_Low/S_High, V_Low/V_High
    1-6: Seleccionar color
    R: Resetear color actual
    S: Guardar y salir
    Q: Cancelar

  Ejecucion:
    C: Re-calibrar esquinas
    B: Calibrar colores HSV
    V: Ver raw (camara sin rectificar)
    Q: Salir
"""

import cv2
import numpy as np
import json
import time
import sys
import os
import tempfile
import shutil

# ============================================================================
# CONFIGURACION
# ============================================================================

CAPTURE_WIDTH = 640
CAPTURE_HEIGHT = 480
CAMERA_INDEX = 0
CAMERA_AUTO_DETECT = True
CAMERA_BACKEND = cv2.CAP_DSHOW
SEND_FREQUENCY = 10
SEND_INTERVAL = 1.0 / SEND_FREQUENCY
MIN_CONTOUR_AREA = 400
MAX_CONTOUR_AREA = 50000

# Archivo compartido para IPC
IPC_DIR = tempfile.gettempdir()
IPC_FILE = os.path.join(IPC_DIR, "secuencia_pieces.json")
IPC_TEMP_FILE = os.path.join(IPC_DIR, "secuencia_pieces.tmp")

# Archivo de configuracion de esquinas (perspective crop)
_script_dir = os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else os.getcwd()
CROP_CONFIG_FILE = os.path.join(_script_dir, "crop_config.json")
COLOR_CONFIG_FILE = os.path.join(_script_dir, "color_config.json")

CORNERS_ORDER = ["tl", "tr", "br", "bl"]
CORNERS_LABELS = ["TL", "TR", "BR", "BL"]

# Output size for the rectified image (after perspective warp)
RECTIFIED_WIDTH = 640
RECTIFIED_HEIGHT = 480

# ============================================================================
# RANGOS HSV
# ============================================================================

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

# ============================================================================
# FUNCIONES DE PERSPECTIVA (CORNER CROP)
# ============================================================================

def load_crop_config():
    """Carga esquinas desde archivo JSON.
    Devuelve lista de tuplas (x, y) en fracciones 0-1, o None si no existe o es invalido.
    Si el archivo existe pero tiene formato antiguo (x,y,w,h), lo borra y retorna None."""
    if not os.path.exists(CROP_CONFIG_FILE):
        return None
    try:
        with open(CROP_CONFIG_FILE, 'r') as f:
            config = json.load(f)
        # Detectar formato antiguo (x, y, w, h) y eliminarlo
        if all(k in config for k in ("x", "y", "w", "h")):
            print(f"[Crop] Formato antiguo detectado. Eliminando {CROP_CONFIG_FILE}...", file=sys.stderr)
            os.remove(CROP_CONFIG_FILE)
            return None
        if "corners" not in config or len(config["corners"]) != 4:
            print(f"[Crop] Config invalida (se requieren 4 esquinas)", file=sys.stderr)
            os.remove(CROP_CONFIG_FILE)
            return None
        corners_in = config["corners"]
        corners = []
        for c in corners_in:
            if not all(k in c for k in ("x", "y")):
                raise ValueError("Formato de esquina invalido")
            corners.append((float(c["x"]), float(c["y"])))
        return corners
    except (json.JSONDecodeError, IOError, ValueError) as e:
        print(f"[Crop] Error leyendo {CROP_CONFIG_FILE}: {e}", file=sys.stderr)
        try:
            os.remove(CROP_CONFIG_FILE)
        except OSError:
            pass
        return None


def save_crop_config(corners_frac):
    """Guarda las 4 esquinas a archivo JSON (formato fracciones 0-1)."""
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
    """Convierte esquinas de fracciones a pixeles."""
    return [(int(round(x * frame_w)), int(round(y * frame_h))) for (x, y) in corners_frac]


# ============================================================================
# FUNCIONES DE CONFIGURACION DE COLORES
# ============================================================================

def save_color_config(color_ranges):
    """Guarda rangos HSV de todos los colores a archivo JSON.
    Escritura atomica: .tmp + shutil.move"""
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
    for color_name in color_ranges:
        d = config[color_name]
        print(f"[Color]   {color_name}: H=[{d['lower'][0]},{d['upper'][0]}] "
              f"S=[{d['lower'][1]},{d['upper'][1]}] V=[{d['lower'][2]},{d['upper'][2]}]",
              file=sys.stderr)


def load_color_config():
    """Carga rangos HSV desde archivo JSON.
    Devuelve dict con formato COLOR_RANGES o None si no existe/invalido."""
    if not os.path.exists(COLOR_CONFIG_FILE):
        return None
    try:
        with open(COLOR_CONFIG_FILE, 'r') as f:
            config = json.load(f)
        expected = list(COLOR_RANGES.keys())
        result = {}
        for color_name in expected:
            if color_name not in config:
                print(f"[Color] '{color_name}' no encontrado en {COLOR_CONFIG_FILE}", file=sys.stderr)
                return None
            c = config[color_name]
            if not all(k in c for k in ("lower", "upper", "bgr")):
                print(f"[Color] '{color_name}' tiene formato invalido", file=sys.stderr)
                return None
            if len(c["lower"]) != 3 or len(c["upper"]) != 3 or len(c["bgr"]) != 3:
                print(f"[Color] '{color_name}' tiene dimensiones incorrectas", file=sys.stderr)
                return None
            result[color_name] = {
                "lower": np.array(c["lower"], dtype=np.uint8),
                "upper": np.array(c["upper"], dtype=np.uint8),
                "bgr": tuple(c["bgr"])
            }
        print(f"[Color] Rangos cargados: {COLOR_CONFIG_FILE}", file=sys.stderr)
        return result
    except (json.JSONDecodeError, IOError, ValueError) as e:
        print(f"[Color] Error leyendo {COLOR_CONFIG_FILE}: {e}", file=sys.stderr)
        return None


# ============================================================================
# FUNCIONES DE PERSPECTIVA (CORNER CROP)
# ============================================================================

def apply_perspective_crop(frame, corners_frac, out_w, out_h):
    """
    Aplica transformacion de perspectiva para rectificar la pantalla.
    Devuelve (imagen_rectificada, matriz_M).
    """
    h, w = frame.shape[:2]
    src_pts = np.array([[x * w, y * h] for (x, y) in corners_frac], dtype=np.float32)
    dst_pts = np.array([[0, 0], [out_w, 0], [out_w, out_h], [0, out_h]], dtype=np.float32)
    M = cv2.getPerspectiveTransform(src_pts, dst_pts)
    warped = cv2.warpPerspective(frame, M, (out_w, out_h))
    return warped, M


def draw_corners_overlay(frame, corners_px):
    """
    Dibuja el poligono de esquinas y oscurece el area exterior.
    corners_px: lista de tuplas (x, y) en pixeles (0 a 4).
    Si esta vacia, devuelve el frame sin modificar.
    """
    if not corners_px:
        return frame.copy()

    h, w = frame.shape[:2]
    pts = np.array(corners_px, np.int32)

    result = frame.copy()

    if len(corners_px) >= 3:
        # Crear mascara para el area interior y oscurecer exterior
        mask = np.zeros((h, w), dtype=np.uint8)
        cv2.fillPoly(mask, [pts], 255)
        overlay = frame.copy()
        overlay[mask == 0] = (overlay[mask == 0] * 0.35).astype(np.uint8)
        result = cv2.addWeighted(overlay, 0.65, frame, 0.35, 0)

    # Poligono / lineas
    if len(corners_px) >= 2:
        cv2.polylines(result, [pts], len(corners_px) == 4, (0, 255, 0), 2)

    # Circulos numerados en cada esquina
    colors = [(0, 255, 255), (255, 0, 0), (0, 0, 255), (0, 255, 0)]
    for i, (cx, cy) in enumerate(corners_px):
        cv2.circle(result, (cx, cy), 8, colors[i], -1)
        cv2.circle(result, (cx, cy), 8, (255, 255, 255), 2)
        label = CORNERS_LABELS[i]
        cv2.putText(result, label, (cx + 12, cy + 6),
                   cv2.FONT_HERSHEY_SIMPLEX, 0.6, colors[i], 2)
        cv2.putText(result, f"{i+1}", (cx - 4, cy + 4),
                   cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)

    return result


# ============================================================================
# FUNCIONES DE DETECCION
# ============================================================================

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
    """Dibuja detecciones directamente sobre el frame (offset 0)."""
    for color_name, centers in detections.items():
        color_bgr = COLOR_RANGES[color_name]["bgr"]
        for cx, cy, contour in centers:
            cv2.drawContours(frame, [contour], 0, color_bgr, 2)
            cv2.circle(frame, (cx, cy), 5, color_bgr, -1)
            cv2.putText(frame, color_name, (cx + 10, cy - 10),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.4, color_bgr, 1)


def format_data(detections, frame_w, frame_h):
    """Normaliza coordenadas respecto al rectificado (0-1)."""
    data = {"piezas": []}
    for color_name, centers in detections.items():
        for cx, cy, _ in centers:
            x_norm = cx / frame_w if frame_w > 0 else 0
            y_norm = cy / frame_h if frame_h > 0 else 0
            data["piezas"].append({
                "color": color_name,
                "x": round(x_norm, 3),
                "y": round(y_norm, 3)
            })
    return data


# ============================================================================
# IPC - Archivo compartido
# ============================================================================

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
            print(f"!ENCONTRADA!", file=sys.stderr)
            return i
        print("no disponible", file=sys.stderr)
    print("[Video] No se encontro camara automaticamente, usando indice por defecto", file=sys.stderr)
    return CAMERA_INDEX


# ============================================================================
# CALIBRACION INTERACTIVA (CLICK EN ESQUINAS)
# ============================================================================

def calibrate_corners(cap):
    """
    Modo interactivo: el usuario hace click en las 4 esquinas del TV.
    Se aplica perspectiva en vivo para previsualizar el rectificado.
    """
    raw_corners = []  # pixeles (x, y), orden: TL, TR, BR, BL
    last_frame = None
    window_name = "Calibracion - Marque 4 esquinas del TV  [C] Guardar  [R] Reset  [U] Undo  [Q] Cancelar"

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

        # Instrucciones
        if len(raw_corners) < 4:
            msg = f"Click en esquina {len(raw_corners) + 1}: {CORNERS_LABELS[len(raw_corners)]}"
            next_idx = min(len(raw_corners), 3)
            color = [(0, 255, 255), (255, 0, 0), (0, 0, 255), (0, 255, 0)][next_idx]
            cv2.putText(display, msg, (10, 30), cv2.FONT_HERSHEY_SIMPLEX,
                       0.6, color, 2)
        else:
            cv2.putText(display, "[C] Confirmar y continuar  [R] Reset  [Q] Cancelar",
                       (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1)

            # Mini preview rectificado en la esquina inferior derecha
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
        last_frame = frame.copy()

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
        h_f, w_f = last_frame.shape[:2]
        corners_frac = [(x / w_f, y / h_f) for (x, y) in raw_corners]
        save_crop_config(corners_frac)
        return corners_frac

    return None


# ============================================================================
# CALIBRACION INTERACTIVA DE COLORES (TRACKBARS HSV)
# ============================================================================

COLOR_NAMES_LIST = list(COLOR_RANGES.keys())


def calibrate_colors(cap, corners_frac, current_ranges):
    """
    Modo interactivo: ajusta rangos HSV por color con trackbars en vivo.
    Muestra el warpeo con mascara superpuesta del color seleccionado.
    [1-6] Color  [R] Reset  [S] Guardar  [Q] Cancelar
    Devuelve dict actualizado o None si se cancelo.
    """
    current_idx = 0

    # Copia de trabajo (evita mutar el original hasta guardar)
    working = {}
    for name, data in current_ranges.items():
        working[name] = {
            "lower": data["lower"].copy(),
            "upper": data["upper"].copy(),
            "bgr": data["bgr"]
        }

    # Copia de rangos por defecto para reset
    defaults = {}
    for name, data in COLOR_RANGES.items():
        defaults[name] = {
            "lower": data["lower"].copy(),
            "upper": data["upper"].copy(),
            "bgr": data["bgr"]
        }

    window_name = "Cal HSV - [1-6] Color  [R] Reset  [S] Guardar  [Q] Salir"
    cv2.namedWindow(window_name)

    # Crear trackbars (valores iniciales se setean despues)
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

        # Leer trackbars
        lo[0] = cv2.getTrackbarPos("H_Low", window_name)
        hi[0] = cv2.getTrackbarPos("H_High", window_name)
        lo[1] = cv2.getTrackbarPos("S_Low", window_name)
        hi[1] = cv2.getTrackbarPos("S_High", window_name)
        lo[2] = cv2.getTrackbarPos("V_Low", window_name)
        hi[2] = cv2.getTrackbarPos("V_High", window_name)

        # Forzar low <= high
        for i in range(3):
            if lo[i] > hi[i]:
                lo[i], hi[i] = hi[i], lo[i]

        # Mascara HSV
        hsv = cv2.cvtColor(warped, cv2.COLOR_BGR2HSV)
        mask = cv2.inRange(hsv, lo, hi)
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)

        # Overlay coloreado
        bgr = working[color_name]["bgr"]
        colored = np.zeros_like(warped)
        colored[mask > 0] = bgr
        display = cv2.addWeighted(warped, 0.6, colored, 0.4, 0)

        # Mini mascara (esquina inferior derecha)
        mask_small = cv2.resize(mask, (120, 90))
        mask_bgr = cv2.cvtColor(mask_small, cv2.COLOR_GRAY2BGR)
        h_disp, w_disp = display.shape[:2]
        ox, oy = w_disp - 130, h_disp - 100
        display[oy:oy + 90, ox:ox + 120] = mask_bgr
        cv2.rectangle(display, (ox - 1, oy - 1),
                     (ox + 121, oy + 91), (200, 200, 200), 1)

        # Contornos del color seleccionado
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

        # Info
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


# ============================================================================
# LOOP PRINCIPAL
# ============================================================================

def print_usage():
    print(file=sys.stderr)
    print("Uso: python secuencia_detector_ipc.py [indice_camara] [--calibrate] [--calibrate-colors]", file=sys.stderr)
    print(file=sys.stderr)
    print("  indice_camara       Numero de dispositivo de camara (0, 1, ...)", file=sys.stderr)
    print("  --calibrate         Forzar calibracion de esquinas (crop)", file=sys.stderr)
    print("  --calibrate-colors  Forzar calibracion de colores HSV", file=sys.stderr)
    print(file=sys.stderr)
    print("  Calibracion de esquinas (--calibrate o tecla C):", file=sys.stderr)
    print("    Click: Marcar esquina (TL->TR->BR->BL)", file=sys.stderr)
    print("    R: Resetear todas las esquinas", file=sys.stderr)
    print("    U: Deshacer ultima esquina", file=sys.stderr)
    print("    C: Guardar y continuar", file=sys.stderr)
    print("    Q: Cancelar", file=sys.stderr)
    print(file=sys.stderr)
    print("  Calibracion de colores (--calibrate-colors o tecla B):", file=sys.stderr)
    print("    Trackbars: Ajustar H_Low/H_High, S_Low/S_High, V_Low/V_High", file=sys.stderr)
    print("    1-6: Seleccionar color (1=yellow ... 6=violet)", file=sys.stderr)
    print("    R: Resetear color actual a valores por defecto", file=sys.stderr)
    print("    S: Guardar y salir", file=sys.stderr)
    print("    Q: Cancelar", file=sys.stderr)
    print(file=sys.stderr)
    print("  Ejecucion:", file=sys.stderr)
    print("    C: Re-calibrar esquinas", file=sys.stderr)
    print("    B: Calibrar colores HSV", file=sys.stderr)
    print("    V: Ver raw (camara sin rectificar)", file=sys.stderr)
    print("    Q: Salir", file=sys.stderr)
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
                print(f"[Video] Indice de camara forzado a {CAMERA_INDEX} por linea de comandos", file=sys.stderr)
            except ValueError:
                print(f"[Video] Ignorando argumento invalido: {arg}", file=sys.stderr)

    print("[SECUENCIA] Iniciando detector de postits (IPC por archivo)", file=sys.stderr)
    print(f"Resolucion: {CAPTURE_WIDTH}x{CAPTURE_HEIGHT}", file=sys.stderr)
    print(f"Rectificado: {RECTIFIED_WIDTH}x{RECTIFIED_HEIGHT}", file=sys.stderr)
    print(f"Archivo IPC: {IPC_FILE}", file=sys.stderr)
    print(f"Archivo esquinas: {CROP_CONFIG_FILE}", file=sys.stderr)
    print(f"Archivo colores: {COLOR_CONFIG_FILE}", file=sys.stderr)
    print(f"Frecuencia envio: {SEND_FREQUENCY} Hz", file=sys.stderr)
    print(f"Backend: DirectShow (CAP_DSHOW)", file=sys.stderr)
    print("-" * 60, file=sys.stderr)

    cam_idx = find_camera()
    cap = cv2.VideoCapture(cam_idx, CAMERA_BACKEND)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    if not cap.isOpened():
        print(f"[ERROR] No se pudo abrir la camara (indice {cam_idx}).", file=sys.stderr)
        return

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, CAPTURE_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAPTURE_HEIGHT)

    # Cargar o calibrar esquinas
    corners_frac = load_crop_config()

    if calibrate_mode or corners_frac is None:
        if corners_frac is None:
            print("[Crop] No hay configuracion guardada. Iniciando calibracion...", file=sys.stderr)
        else:
            print("[Crop] Modo calibracion forzado por --calibrate", file=sys.stderr)
        result = calibrate_corners(cap)
        if result is not None:
            corners_frac = result
        elif corners_frac is None:
            print("[ERROR] No hay configuracion de esquinas. Saliendo.", file=sys.stderr)
            cap.release()
            return

    print(f"[Crop] Esquinas activas:", file=sys.stderr)
    h_frame, w_frame = CAPTURE_HEIGHT, CAPTURE_WIDTH
    for i, label in enumerate(CORNERS_LABELS):
        x, y = corners_frac[i]
        px, py = int(x * w_frame), int(y * h_frame)
        print(f"[Crop]   {label}: frac=({x:.3f}, {y:.3f}) px=({px}, {py})", file=sys.stderr)

    # Cargar o calibrar colores
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
                print("[ERROR] No se pudo leer frame de camara.", file=sys.stderr)
                break

            # Aplicar perspectiva: rectificar la pantalla
            warped, M = apply_perspective_crop(
                frame, corners_frac, RECTIFIED_WIDTH, RECTIFIED_HEIGHT
            )

            # Detectar sobre la imagen rectificada
            detections = {}
            for color_name in COLOR_RANGES.keys():
                detections[color_name] = detect_color(warped, color_name, COLOR_RANGES[color_name])

            # Elegir vista
            if show_raw:
                h_f, w_f = frame.shape[:2]
                corners_px = corners_to_pixels(corners_frac, w_f, h_f)
                display = draw_corners_overlay(frame, corners_px)
                # Mini vista rectificada
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
            cv2.putText(display, f"IPC activo | Perspectiva activa", (10, 80),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 255, 0), 1)

            cv2.imshow(window_name, display)

            # Enviar datos (coordenadas sobre el rectificado)
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
                    print(f"[Crop] Nuevas esquinas activas", file=sys.stderr)
            elif key == ord('b') or key == ord('B'):
                print("\n[Color] Calibrando colores...", file=sys.stderr)
                result = calibrate_colors(cap, corners_frac, COLOR_RANGES)
                if result is not None:
                    COLOR_RANGES.clear()
                    COLOR_RANGES.update(result)
                    print(f"[Color] Nuevos rangos activos", file=sys.stderr)
            elif key == ord('v') or key == ord('V'):
                show_raw = not show_raw
                print(f"[View] {'RAW' if show_raw else 'RECTIFICADO'}", file=sys.stderr)

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
