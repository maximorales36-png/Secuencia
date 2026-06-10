#!/usr/bin/env python3
"""
SECUENCIA - Detector de Postits (IPC por archivo)
Detecta postits de colores en tiempo real y escribe posiciones
a un archivo JSON compartido para que Godot lo lea.
Sin dependencia de red — funciona sin WiFi.
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
# CONFIGURACIÓN
# ============================================================================

CAPTURE_WIDTH = 640
CAPTURE_HEIGHT = 480
CAMERA_INDEX = 0
CAMERA_AUTO_DETECT = True
CAMERA_BACKEND = cv2.CAP_MSMF  # Microsoft Media Foundation (recomendado para Windows moderno)
SEND_FREQUENCY = 10
SEND_INTERVAL = 1.0 / SEND_FREQUENCY
MIN_CONTOUR_AREA = 400
MAX_CONTOUR_AREA = 50000

# Archivo compartido para IPC
IPC_DIR = tempfile.gettempdir()
IPC_FILE = os.path.join(IPC_DIR, "secuencia_pieces.json")
IPC_TEMP_FILE = os.path.join(IPC_DIR, "secuencia_pieces.tmp")

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
# FUNCIONES DE DETECCIÓN
# ============================================================================

def normalize_point(x, y, width, height):
    return (x / width, y / height)

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

def format_data(detections, width, height):
    data = {"piezas": []}
    for color_name, centers in detections.items():
        for cx, cy, _ in centers:
            x_norm, y_norm = normalize_point(cx, cy, width, height)
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
    """Escribe datos como JSON a archivo compartido (escritura atómica)."""
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
    for i in range(5):  # Solo probar primeros 5 índices para evitar cuelgues
        print(f"[Video] Probando cámara en índice {i}...", file=sys.stderr, end=" ", flush=True)
        cap = cv2.VideoCapture(i, CAMERA_BACKEND)
        if cap.isOpened():
            cap.release()
            print(f"¡ENCONTRADA!", file=sys.stderr)
            return i
        print("no disponible", file=sys.stderr)
    print("[Video] No se encontró cámara automáticamente, usando índice por defecto", file=sys.stderr)
    return CAMERA_INDEX

# ============================================================================
# LOOP PRINCIPAL
# ============================================================================

def main():
    global CAMERA_INDEX

    if len(sys.argv) > 1:
        try:
            CAMERA_INDEX = int(sys.argv[1])
            print(f"[Video] Índice de cámara forzado a {CAMERA_INDEX} por línea de comandos", file=sys.stderr)
        except ValueError:
            print(f"[Video] Ignorando argumento inválido: {sys.argv[1]}", file=sys.stderr)

    print("[SECUENCIA] Iniciando detector de postits (IPC por archivo)", file=sys.stderr)
    print(f"Resolución: {CAPTURE_WIDTH}x{CAPTURE_HEIGHT}", file=sys.stderr)
    print(f"Archivo IPC: {IPC_FILE}", file=sys.stderr)
    print(f"Frecuencia envío: {SEND_FREQUENCY} Hz", file=sys.stderr)
    print(f"Backend: DirectShow (CAP_DSHOW)", file=sys.stderr)
    print("-" * 60, file=sys.stderr)

    cam_idx = find_camera()
    cap = cv2.VideoCapture(cam_idx, CAMERA_BACKEND)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    if not cap.isOpened():
        print(f"[ERROR] No se pudo abrir la cámara (índice {cam_idx}).", file=sys.stderr)
        return

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, CAPTURE_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAPTURE_HEIGHT)

    last_send_time = time.time()
    frame_count = 0
    running = True

    try:
        while running:
            ret, frame = cap.read()
            if not ret:
                print("[ERROR] No se pudo leer frame de cámara.", file=sys.stderr)
                break

            detections = {}
            for color_name in COLOR_RANGES.keys():
                detections[color_name] = detect_color(frame, color_name, COLOR_RANGES[color_name])

            draw_detections(frame, detections)

            cv2.putText(frame, f"Frame: {frame_count}", (10, 30),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200, 200, 200), 1)
            total_pieces = sum(len(centers) for centers in detections.values())
            cv2.putText(frame, f"Piezas: {total_pieces}", (10, 60),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200, 200, 200), 1)
            cv2.putText(frame, f"IPC activo", (10, 90),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 1)

            cv2.imshow("SECUENCIA - Detector (IPC)", frame)

            current_time = time.time()
            if current_time - last_send_time >= SEND_INTERVAL:
                data = format_data(detections, CAPTURE_WIDTH, CAPTURE_HEIGHT)
                send_data(data)
                last_send_time = current_time

            frame_count += 1

            key = cv2.waitKey(1) & 0xFF
            if key == ord('q') or key == ord('Q'):
                print("\n[OK] Saliendo...", file=sys.stderr)
                running = False
                break

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
