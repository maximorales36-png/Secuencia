#!/usr/bin/env python3
"""
SECUENCIA v4 - Detector YOLO exclusivo
Deteccion de piezas 3D mediante YOLO, sin backend HSV.

Uso:
  python secuencia_detector_ipc_v4.py [indice_camara] [--calibrate]
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
CAPTURE_HEIGHT = 400
CAMERA_INDEX = 0
CAMERA_AUTO_DETECT = True
CAMERA_BACKEND = cv2.CAP_DSHOW
SEND_FREQUENCY = 10
SEND_INTERVAL = 1.0 / SEND_FREQUENCY

PX_PER_MM = None
MIN_CONSECUTIVE_FRAMES = 3
DETECTION_MEMORY_TIMEOUT = 0.5
DETECTION_STABILIZE_SNAP = 0.02
MIRROR_X = True
MIRROR_Y = True
DEBUG_MODE = False

IPC_DIR = tempfile.gettempdir()
IPC_FILE = os.path.join(IPC_DIR, "secuencia_pieces.json")
IPC_TEMP_FILE = os.path.join(IPC_DIR, "secuencia_pieces.tmp")

_script_dir = os.path.dirname(os.path.abspath(__file__))
CROP_CONFIG_FILE = os.path.join(_script_dir, "crop_config.json")

CORNERS_ORDER = ["tl", "tr", "br", "bl"]
CORNERS_LABELS = ["TL", "TR", "BR", "BL"]

RECTIFIED_WIDTH = 640
RECTIFIED_HEIGHT = 480
YOLO_CONF_THRESHOLD = 0.85

CORNERS_OVERLAY_COLORS = [(0, 255, 255), (255, 0, 0), (0, 0, 255), (0, 255, 0)]

_YOLO_MODEL = None


def get_yolo_model():
    global _YOLO_MODEL
    if _YOLO_MODEL is not None:
        return _YOLO_MODEL
    model_path = os.path.join(_script_dir, "modelos", "yolo26n.pt")
    if not os.path.exists(model_path):
        print(f"[YOLO] Modelo no encontrado: {model_path}", file=sys.stderr)
        return None
    try:
        from ultralytics import YOLO
        _YOLO_MODEL = YOLO(model_path)
        print(f"[YOLO] Modelo cargado: {model_path}", file=sys.stderr)
        return _YOLO_MODEL
    except Exception as e:
        print(f"[YOLO] Error cargando modelo: {e}", file=sys.stderr)
        return None


def detect_yolo(warped):
    model = get_yolo_model()
    if model is None:
        return {}
    results = model(warped, verbose=False)
    detections = {}
    for r in results:
        if r.boxes is None:
            continue
        for box, cls_id, conf in zip(r.boxes.xyxy, r.boxes.cls, r.boxes.conf):
            if conf < YOLO_CONF_THRESHOLD:
                continue
            x1, y1, x2, y2 = map(int, box.tolist())
            cx = (x1 + x2) // 2
            cy = (y1 + y2) // 2
            label = model.names[int(cls_id)]
            if label not in detections:
                detections[label] = []
            detections[label].append((cx, cy))
    total = sum(len(v) for v in detections.values())
    if total == 0 and DEBUG_MODE:
        for r in results:
            if r.boxes is not None and len(r.boxes) > 0:
                for b, c, conf in zip(r.boxes.xyxy, r.boxes.cls, r.boxes.conf):
                    print(f"[YOLO] baja conf: {model.names[int(c)]} conf={conf:.3f}", file=sys.stderr)
    return detections


def create_roi_mask(frame_shape, corners_px):
    mask = np.zeros(frame_shape[:2], dtype=np.uint8)
    pts = np.array(corners_px, np.int32)
    cv2.fillPoly(mask, [pts], 255)
    return mask


def update_detection_memory(raw_detections, memory, now):
    for key in memory:
        memory[key]["matched"] = False

    for color_name, centers in raw_detections.items():
        for cx, cy in centers:
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

    expired = [k for k, m in memory.items() if now - m["last_seen"] > DETECTION_MEMORY_TIMEOUT]
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


def load_crop_config():
    global PX_PER_MM
    if not os.path.exists(CROP_CONFIG_FILE):
        return None
    try:
        with open(CROP_CONFIG_FILE, 'r') as f:
            config = json.load(f)
        if all(k in config for k in ("x", "y", "w", "h")):
            print(f"[Crop] Formato antiguo, eliminando...", file=sys.stderr)
            os.remove(CROP_CONFIG_FILE)
            return None
        if "corners" not in config or len(config["corners"]) != 4:
            print(f"[Crop] Config invalida", file=sys.stderr)
            os.remove(CROP_CONFIG_FILE)
            return None
        corners = []
        for c in config["corners"]:
            if not all(k in c for k in ("x", "y")):
                raise ValueError("Formato invalido")
            corners.append((float(c["x"]), float(c["y"])))
        if "screen_width_mm" in config and config["screen_width_mm"] > 0:
            PX_PER_MM = RECTIFIED_WIDTH / config["screen_width_mm"]
        return corners
    except (json.JSONDecodeError, IOError, ValueError) as e:
        print(f"[Crop] Error: {e}", file=sys.stderr)
        try:
            os.remove(CROP_CONFIG_FILE)
        except OSError:
            pass
        return None


def save_crop_config(corners_frac, screen_width_mm=None):
    existing = {}
    if os.path.exists(CROP_CONFIG_FILE):
        try:
            with open(CROP_CONFIG_FILE, 'r') as f:
                existing = json.load(f)
        except Exception:
            pass

    config = {
        "order": CORNERS_ORDER,
        "corners": [{"x": round(x, 4), "y": round(y, 4)} for (x, y) in corners_frac]
    }
    if screen_width_mm is not None and screen_width_mm > 0:
        config["screen_width_mm"] = screen_width_mm
    elif "screen_width_mm" in existing:
        config["screen_width_mm"] = existing["screen_width_mm"]

    tmp = CROP_CONFIG_FILE + ".tmp"
    with open(tmp, 'w') as f:
        json.dump(config, f, indent=2)
        f.flush()
        os.fsync(f.fileno())
    shutil.move(tmp, CROP_CONFIG_FILE)
    print(f"[Crop] Esquinas guardadas: {CROP_CONFIG_FILE}", file=sys.stderr)


def corners_to_pixels(corners_frac, frame_w, frame_h):
    return [(int(round(x * frame_w)), int(round(y * frame_h))) for (x, y) in corners_frac]


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


COLOR_BGR_MAP = {
    "red":    (0, 0, 255),
    "pink":   (255, 192, 203),
    "green":  (0, 255, 80),
    "blue":   (255, 0, 0),
    "violet": (255, 0, 255),
}


def draw_detections(frame, detections):
    for color_name, centers in detections.items():
        color_bgr = COLOR_BGR_MAP.get(color_name, (200, 200, 200))
        for cx, cy in centers:
            cv2.circle(frame, (cx, cy), 8, color_bgr, -1)
            cv2.circle(frame, (cx, cy), 10, (255, 255, 255), 1)
            cv2.putText(frame, color_name, (cx + 12, cy - 10),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.4, color_bgr, 1)


def draw_hud(frame, lines, x=8, y=22, line_h=20):
    for text, color in lines:
        cv2.rectangle(frame, (x - 4, y - line_h + 4), (x + len(text) * 8 + 4, y + 2), (0, 0, 0, 0.6), -1)
        cv2.putText(frame, text, (x, y), cv2.FONT_HERSHEY_SIMPLEX, 0.45, color, 1)
        y += line_h


def format_data(detections, frame_w, frame_h):
    data = {"piezas": []}
    for color_name, centers in detections.items():
        for cx, cy in centers:
            x_norm = round(cx / frame_w, 3) if frame_w > 0 else 0
            if MIRROR_X:
                x_norm = round(1.0 - x_norm, 3)
            y_norm = round(cy / frame_h, 3) if frame_h > 0 else 0
            if MIRROR_Y:
                y_norm = round(1.0 - y_norm, 3)
            data["piezas"].append({
                "color": color_name,
                "x": x_norm,
                "y": y_norm
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
    window_name = "Calibracion - Marque 4 esquinas (orden TL->TR->BR->BL)"

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
        if os.path.exists(CROP_CONFIG_FILE):
            try:
                with open(CROP_CONFIG_FILE, 'r') as f:
                    existing = json.load(f)
                if "screen_width_mm" in existing and existing["screen_width_mm"] > 0:
                    screen_width_mm = existing["screen_width_mm"]
                    global PX_PER_MM
                    PX_PER_MM = RECTIFIED_WIDTH / screen_width_mm
                    print(f"[Crop] px_per_mm reutilizado: {PX_PER_MM:.4f} (screen_width={screen_width_mm}mm)", file=sys.stderr)
            except Exception:
                pass

        try:
            save_crop_config(corners_frac, screen_width_mm)
        except Exception as e:
            print(f"[Crop] Error al guardar config: {e}", file=sys.stderr)
        return corners_frac
    return None


def print_usage():
    print(file=sys.stderr)
    print("Uso: python secuencia_detector_ipc_v4.py [indice_camara] [--calibrate]", file=sys.stderr)
    print(file=sys.stderr)
    print("  --calibrate         Forzar calibracion de esquinas", file=sys.stderr)
    print("  C: Re-calibrar esquinas   V: Ver raw   Q: Salir", file=sys.stderr)
    print("  M: Mirror X   N: Mirror Y   D: Debug", file=sys.stderr)
    print(file=sys.stderr)


def main():
    global CAMERA_INDEX, PX_PER_MM, MIRROR_X, MIRROR_Y, DEBUG_MODE

    calibrate_mode = False
    for arg in sys.argv[1:]:
        if arg == "--calibrate":
            calibrate_mode = True
        elif arg == "--help" or arg == "-h":
            print_usage()
            return
        else:
            try:
                CAMERA_INDEX = int(arg)
                print(f"[Video] Indice de camara forzado a {CAMERA_INDEX}", file=sys.stderr)
            except ValueError:
                print(f"[Video] Ignorando argumento invalido: {arg}", file=sys.stderr)

    print("[SECUENCIA v4] Iniciando detector YOLO", file=sys.stderr)
    print(f"Resolucion: {CAPTURE_WIDTH}x{CAPTURE_HEIGHT}", file=sys.stderr)
    print(f"Rectificado: {RECTIFIED_WIDTH}x{RECTIFIED_HEIGHT}", file=sys.stderr)
    print(f"IPC: {IPC_FILE}", file=sys.stderr)
    print(f"Frecuencia: {SEND_FREQUENCY} Hz", file=sys.stderr)
    print(f"Threshold YOLO: {YOLO_CONF_THRESHOLD}", file=sys.stderr)
    print(f"Mirror X: {'ON' if MIRROR_X else 'OFF'}  Mirror Y: {'ON' if MIRROR_Y else 'OFF'}", file=sys.stderr)
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

    last_send_time = time.time()
    frame_count = 0
    running = True
    window_name = "SECUENCIA v4 - YOLO Detector"
    show_raw = False

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

            warped, M = apply_perspective_crop(frame, corners_frac, RECTIFIED_WIDTH, RECTIFIED_HEIGHT)

            raw_detections = detect_yolo(warped)

            now = time.time()
            detections = update_detection_memory(raw_detections, detection_memory, now)

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
            else:
                display = warped.copy()

            # --- HUD con fondo oscuro ---
            total_pieces = sum(len(centers) for centers in detections.values())
            mode_label = "RAW" if show_raw else "RECT"
            mirror_str = (" MX" if MIRROR_X else "") + (" MY" if MIRROR_Y else "")
            raw_count = sum(len(c) for c in raw_detections.values())
            mem_count = len(detection_memory)

            draw_hud(display, [
                (f"v4 Frame: {frame_count} | {mode_label}{mirror_str}", (0, 255, 0)),
                (f"Piezas: {total_pieces} (yolo:{raw_count} mem:{mem_count})", (200, 200, 200)),
            ])

            if not show_raw:
                draw_detections(display, detections)

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
            elif key == ord('v') or key == ord('V'):
                show_raw = not show_raw
            elif key == ord('m') or key == ord('M'):
                MIRROR_X = not MIRROR_X
                print(f"\n[v4] Mirror X: {'ON' if MIRROR_X else 'OFF'}", file=sys.stderr)
            elif key == ord('n') or key == ord('N'):
                MIRROR_Y = not MIRROR_Y
                print(f"\n[v4] Mirror Y: {'ON' if MIRROR_Y else 'OFF'}", file=sys.stderr)
            elif key == ord('d') or key == ord('D'):
                DEBUG_MODE = not DEBUG_MODE
                print(f"\n[v4] Debug: {'ON' if DEBUG_MODE else 'OFF'}", file=sys.stderr)

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
