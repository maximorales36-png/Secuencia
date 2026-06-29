#!/usr/bin/env python3
"""
SECUENCIA - Visualizador HSV (fullscreen, trail FX)
Muestra la cámara secundaria en pantalla completa con detección HSV
y efecto de estela (trail) con decaimiento gradual.

Sin IPC: no escribe archivos, solo visualización.

Uso:
  python secuencia_hsv_visualizer.py [indice_camara] [--monitor N] [--decay FACTOR]
"""

import cv2
import numpy as np
import json
import time
import sys
import os
import ctypes

CAPTURE_WIDTH = 640
CAPTURE_HEIGHT = 400
CAMERA_INDEX = 1
CAMERA_AUTO_DETECT = True
CAMERA_BACKEND = cv2.CAP_DSHOW
MONITOR_INDEX = 2
DECAY_FACTOR = 0.92
MIN_CONTOUR_AREA = 400
MAX_CONTOUR_AREA = 50000

_script_dir = os.path.dirname(os.path.abspath(__file__))
COLOR_CONFIG_FILE = os.path.join(_script_dir, "color_config.json")

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


def find_camera():
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


def get_screen_resolution():
    try:
        user32 = ctypes.windll.user32
        w = user32.GetSystemMetrics(0)
        h = user32.GetSystemMetrics(1)
        return w, h
    except Exception:
        return 1920, 1080


def detect_colors(frame):
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    results = {}
    for color_name, color_range in COLOR_RANGES.items():
        mask = cv2.inRange(hsv, color_range["lower"], color_range["upper"])
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        detections = []
        for contour in contours:
            area = cv2.contourArea(contour)
            if MIN_CONTOUR_AREA < area < MAX_CONTOUR_AREA:
                M = cv2.moments(contour)
                if M["m00"] > 0:
                    cx = int(M["m10"] / M["m00"])
                    cy = int(M["m01"] / M["m00"])
                    detections.append((cx, cy, contour))
        if detections:
            results[color_name] = detections
    return results


def draw_detections(canvas, detections):
    for color_name, items in detections.items():
        color_bgr = COLOR_RANGES[color_name]["bgr"]
        for cx, cy, contour in items:
            cv2.drawContours(canvas, [contour], 0, color_bgr, 2)
            cv2.circle(canvas, (cx, cy), 5, color_bgr, -1)
            cv2.putText(canvas, color_name, (cx + 10, cy - 10),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.4, color_bgr, 1)


def fit_frame_to_screen(frame, screen_w, screen_h, fill=False):
    h, w = frame.shape[:2]
    if fill:
        return cv2.resize(frame, (screen_w, screen_h), interpolation=cv2.INTER_NEAREST)
    scale = min(screen_w / w, screen_h / h)
    new_w = int(w * scale)
    new_h = int(h * scale)
    resized = cv2.resize(frame, (new_w, new_h), interpolation=cv2.INTER_NEAREST)
    canvas = np.zeros((screen_h, screen_w, 3), dtype=np.uint8)
    x_off = (screen_w - new_w) // 2
    y_off = (screen_h - new_h) // 2
    canvas[y_off:y_off + new_h, x_off:x_off + new_w] = resized
    return canvas


def build_dual_display(frame, invert_bottom=True, separator_color=(0, 255, 255)):
    h, w = frame.shape[:2]
    bottom = cv2.bitwise_not(frame) if invert_bottom else frame.copy()
    stacked = np.vstack([frame, bottom])
    if separator_color is not None:
        cv2.line(stacked, (0, h), (w - 1, h), separator_color, 2)
    return stacked


def print_usage():
    print(file=sys.stderr)
    print("Uso: python secuencia_hsv_visualizer.py [indice_camara] [opciones]", file=sys.stderr)
    print(file=sys.stderr)
    print("  indice_camara       Indice de camara (default: 1)", file=sys.stderr)
    print("  --monitor N         Monitor para fullscreen (default: 2)", file=sys.stderr)
    print("  --decay FACTOR      Velocidad de fade del trail (0.0-1.0, default: 0.92)", file=sys.stderr)
    print("  --no-fullscreen     Arrancar en ventana", file=sys.stderr)
    print("  --cam-width W       Resolucion camara ancho (default: 640)", file=sys.stderr)
    print("  --cam-height H      Resolucion camara alto (default: 400)", file=sys.stderr)
    print("  --fill              Estirar imagen para llenar pantalla", file=sys.stderr)
    print("  --single            Una sola imagen (sin duplicado vertical)", file=sys.stderr)
    print("  --no-invert         En modo dual, no invertir la mitad inferior", file=sys.stderr)
    print(file=sys.stderr)
    print("  Q: Salir   F: Toggle fullscreen   +-: Decay   D: Debug", file=sys.stderr)
    print("  T: Toggle single/dual   I: Toggle invert inferior", file=sys.stderr)
    print(file=sys.stderr)


def main():
    global CAPTURE_WIDTH, CAPTURE_HEIGHT, CAMERA_INDEX, CAMERA_AUTO_DETECT, MONITOR_INDEX, DECAY_FACTOR

    no_fullscreen = False
    fill = False
    dual_mode = True
    invert_bottom = True
    for arg in sys.argv[1:]:
        if arg == "--help" or arg == "-h":
            print_usage()
            return
        elif arg == "--no-fullscreen":
            no_fullscreen = True
        elif arg == "--fill":
            fill = True
        elif arg == "--single":
            dual_mode = False
        elif arg == "--no-invert":
            invert_bottom = False
        elif arg.startswith("--monitor"):
            try:
                idx = sys.argv.index(arg)
                MONITOR_INDEX = int(sys.argv[idx + 1])
            except (ValueError, IndexError):
                pass
        elif arg.startswith("--decay"):
            try:
                idx = sys.argv.index(arg)
                DECAY_FACTOR = float(sys.argv[idx + 1])
                DECAY_FACTOR = max(0.0, min(1.0, DECAY_FACTOR))
            except (ValueError, IndexError):
                pass
        elif arg.startswith("--cam-width"):
            try:
                idx = sys.argv.index(arg)
                CAPTURE_WIDTH = int(sys.argv[idx + 1])
            except (ValueError, IndexError):
                pass
        elif arg.startswith("--cam-height"):
            try:
                idx = sys.argv.index(arg)
                CAPTURE_HEIGHT = int(sys.argv[idx + 1])
            except (ValueError, IndexError):
                pass
        else:
            try:
                CAMERA_INDEX = int(arg)
                CAMERA_AUTO_DETECT = False
                print(f"[Video] Indice de camara forzado a {CAMERA_INDEX}", file=sys.stderr)
            except ValueError:
                pass

    print("[SECUENCIA HSV] Iniciando visualizador HSV", file=sys.stderr)
    print(f"Resolucion: {CAPTURE_WIDTH}x{CAPTURE_HEIGHT}", file=sys.stderr)
    print(f"Camara indice: {CAMERA_INDEX}", file=sys.stderr)
    print(f"Monitor: {MONITOR_INDEX}", file=sys.stderr)
    print(f"Decay: {DECAY_FACTOR}", file=sys.stderr)
    print(f"Fullscreen: {'NO' if no_fullscreen else 'YES'}", file=sys.stderr)
    print(f"Fill: {'YES' if fill else 'NO (aspect ratio)'}", file=sys.stderr)
    print(f"Dual: {'YES' if dual_mode else 'NO'}  Invert: {'YES' if invert_bottom else 'NO'}", file=sys.stderr)
    print("-" * 60, file=sys.stderr)

    loaded = load_color_config()
    if loaded:
        COLOR_RANGES.clear()
        COLOR_RANGES.update(loaded)

    cam_idx = find_camera() if CAMERA_AUTO_DETECT else CAMERA_INDEX
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

    screen_w, screen_h = get_screen_resolution()
    print(f"[Video] Resolucion pantalla primaria: {screen_w}x{screen_h}", file=sys.stderr)

    window_name = "SECUENCIA HSV - Visualizer"
    cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)

    if not no_fullscreen:
        offset_x = MONITOR_INDEX * screen_w
        cv2.moveWindow(window_name, offset_x, 0)
        cv2.setWindowProperty(window_name, cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN)

    canvas = None
    is_fullscreen = not no_fullscreen
    decay = DECAY_FACTOR
    debug = False
    dual_mode = dual_mode
    invert_bottom = invert_bottom
    running = True
    frame_count = 0
    fps = 0.0
    fps_counter = 0
    last_fps_time = time.time()

    try:
        while running:
            ret, frame = cap.read()
            if not ret:
                print("[ERROR] No se pudo leer frame.", file=sys.stderr)
                break

            raw_frame = frame.copy()
            h, w = raw_frame.shape[:2]

            if canvas is None or canvas.shape[:2] != (h, w):
                canvas = np.zeros((h, w, 3), dtype=np.uint8)

            detections = detect_colors(raw_frame)

            total_pieces = sum(len(v) for v in detections.values())

            canvas = (canvas * decay).astype(np.uint8)

            draw_detections(canvas, detections)

            display = cv2.addWeighted(raw_frame, 0.3, canvas, 0.7, 0)

            now = time.time()
            fps_counter += 1
            elapsed = now - last_fps_time
            if elapsed >= 0.5:
                fps = fps_counter / elapsed
                fps_counter = 0
                last_fps_time = now

            if debug:
                frame_count += 1
                info_lines = [
                    f"FPS: {fps:.1f}",
                    f"Decay: {decay:.2f}",
                    f"Piezas: {total_pieces}",
                    f"Dual: {'ON' if dual_mode else 'OFF'}  {'Inv' if invert_bottom else ''}"
                ]
                y_offset = 25
                for line in info_lines:
                    cv2.putText(display, line, (10, y_offset),
                               cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1)
                    y_offset += 22

            source_for_output = display
            if dual_mode:
                source_for_output = build_dual_display(display, invert_bottom=invert_bottom)

            if fill:
                output = cv2.resize(source_for_output, (screen_w, screen_h), interpolation=cv2.INTER_NEAREST)
            else:
                output = fit_frame_to_screen(source_for_output, screen_w, screen_h, fill=False)

            cv2.imshow(window_name, output)

            key = cv2.waitKey(1) & 0xFF
            if key == ord('q') or key == ord('Q'):
                print("\n[OK] Saliendo...", file=sys.stderr)
                running = False
                break
            elif key == ord('f') or key == ord('F'):
                is_fullscreen = not is_fullscreen
                if is_fullscreen:
                    offset_x = MONITOR_INDEX * screen_w
                    cv2.moveWindow(window_name, offset_x, 0)
                    cv2.setWindowProperty(window_name, cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN)
                else:
                    cv2.setWindowProperty(window_name, cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_NORMAL)
                    cv2.resizeWindow(window_name, w, h)
                print(f"[Video] Fullscreen: {'ON' if is_fullscreen else 'OFF'}", file=sys.stderr)
            elif key == ord('=') or key == ord('+'):
                decay = min(1.0, decay + 0.03)
                print(f"[FX] Decay: {decay:.2f}", file=sys.stderr)
            elif key == ord('-') or key == ord('_'):
                decay = max(0.0, decay - 0.03)
                print(f"[FX] Decay: {decay:.2f}", file=sys.stderr)
            elif key == ord('d') or key == ord('D'):
                debug = not debug
                print(f"[Debug] {'ON' if debug else 'OFF'}", file=sys.stderr)
            elif key == ord('t') or key == ord('T'):
                dual_mode = not dual_mode
                print(f"[Dual] {'ON' if dual_mode else 'OFF'}", file=sys.stderr)
            elif key == ord('i') or key == ord('I'):
                invert_bottom = not invert_bottom
                print(f"[Invert] {'ON' if invert_bottom else 'OFF'}", file=sys.stderr)

    except KeyboardInterrupt:
        print("\n[OK] Interrumpido por usuario.", file=sys.stderr)
        running = False

    finally:
        cap.release()
        cv2.destroyAllWindows()
        print("[OK] Recursos liberados.", file=sys.stderr)


if __name__ == "__main__":
    main()
