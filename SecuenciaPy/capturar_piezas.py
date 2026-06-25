#!/usr/bin/env python3
"""
Script de captura de fotos para entrenar YOLO.
Guarda frames rectificados limpios (sin overlays) en carpetas por color.

Uso:
  python capturar_piezas.py
  [ESPACIO] guardar frame actual en la carpeta activa
  [1-5]     cambiar carpeta activa (1=red, 2=pink, 3=green, 4=blue, 5=violet)
  [0]       carpeta background (negativas, sin piezas)
  [Q]       salir
"""

import cv2
import numpy as np
import json
import os
import sys
import time

_script_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _script_dir)

from secuencia_detector_ipc_v3 import (
    find_camera, CAMERA_BACKEND, CAPTURE_WIDTH, CAPTURE_HEIGHT,
    RECTIFIED_WIDTH, RECTIFIED_HEIGHT,
    load_crop_config, apply_perspective_crop, calibrate_corners
)

FOLDERS = ["background", "red", "pink", "green", "blue", "violet"]
OUT_DIR = os.path.join(_script_dir, "capturas_yolo")

for f in FOLDERS:
    os.makedirs(os.path.join(OUT_DIR, f), exist_ok=True)

cam_idx = find_camera()
cap = cv2.VideoCapture(cam_idx, CAMERA_BACKEND)
cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
cap.set(cv2.CAP_PROP_FRAME_WIDTH, CAPTURE_WIDTH)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAPTURE_HEIGHT)

corners_frac = load_crop_config()
if corners_frac is None:
    print("[Captura] Sin calibracion. Iniciando calibracion...")
    corners_frac = calibrate_corners(cap)
    if corners_frac is None:
        print("[ERROR] No hay calibracion")
        cap.release()
        sys.exit(1)

active_idx = 1
counters = {f: len(os.listdir(os.path.join(OUT_DIR, f))) for f in FOLDERS}

print(f"[Captura] Guardando en: {OUT_DIR}")
print(f"  [0] background  ({counters['background']}已有的)")
print(f"  [1] red         ({counters['red']}已有的)")
print(f"  [2] pink        ({counters['pink']}已有的)")
print(f"  [3] green       ({counters['green']}已有的)")
print(f"  [4] blue        ({counters['blue']}已有的)")
print(f"  [5] violet      ({counters['violet']}已有的)")
print(f"  [ESPACIO] capturar  [Q] salir")

while True:
    ret, frame = cap.read()
    if not ret:
        break

    warped, _ = apply_perspective_crop(frame, corners_frac, RECTIFIED_WIDTH, RECTIFIED_HEIGHT)
    folder = FOLDERS[active_idx]
    label = folder.upper()

    cv2.putText(warped, f"[{active_idx}] {label}", (10, 30),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)
    cv2.putText(warped, "ESPACIO: capturar  0-5: cambiar carpeta  Q: salir",
                (10, 55), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (200, 200, 200), 1)
    cv2.imshow("Captura YOLO - frame limpio (sin deteccion)", warped)

    key = cv2.waitKey(1) & 0xFF
    if key == ord('q') or key == ord('Q'):
        break
    elif key == ord(' '):
        counters[folder] += 1
        filename = f"{folder}_{counters[folder]:04d}.jpg"
        path = os.path.join(OUT_DIR, folder, filename)
        cv2.imwrite(path, warped)
        print(f"[OK] {filename}")
    elif ord('0') <= key <= ord('5'):
        active_idx = key - ord('0')
        print(f"[Carpeta] -> {FOLDERS[active_idx]}")

cap.release()
cv2.destroyAllWindows()
print("[OK] Captura finalizada")
