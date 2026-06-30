#!/usr/bin/env python3
"""
Test de cámaras - enumera índices disponibles con propiedades.
Correr con: python test_cameras.py
"""

import cv2
import numpy as np

MAX_INDEX = 9


def test_camera(index):
    cap = cv2.VideoCapture(index, cv2.CAP_DSHOW)
    if not cap.isOpened():
        return None

    info = {"index": index}

    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1920)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 1080)
    w_max = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h_max = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    w_min = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h_min = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    ret, frame = cap.read()
    if ret and frame is not None:
        h_actual, w_actual = frame.shape[:2]
        info["actual_res"] = (w_actual, h_actual)
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        info["brightness"] = int(np.mean(gray))
    else:
        info["actual_res"] = (w_min, h_min)
        info["brightness"] = None

    cap.release()

    info["max_res"] = (w_max, h_max)
    info["min_res"] = (w_min, h_min)

    return info


def identify_camera(info):
    w, h = info["max_res"]
    if w >= 1920:
        return "HD Pro WebCam C920 (posible)"
    if w <= 640:
        return "USB 2.0 PC Cam / cámara básica (posible)"
    return "Cámara desconocida"


def main():
    print("=" * 60)
    print("ESCANEO DE CÁMARAS")
    print("=" * 60)

    found = False
    for i in range(MAX_INDEX + 1):
        info = test_camera(i)
        if info is None:
            continue

        found = True
        guess = identify_camera(info)
        print(f"\n[Índice {i}]")
        print(f"  Resolución máxima posible: {info['max_res'][0]}x{info['max_res'][1]}")
        print(f"  Resolución al leer:        {info['actual_res'][0]}x{info['actual_res'][1]}")
        if info["brightness"] is not None:
            print(f"  Brillo promedio:           {info['brightness']}")
        print(f"  ➜ {guess}")

        ret = input(f"\n  ¿Es esta la C920? (s/N): ")
        if ret.lower() == "s":
            print(f"\n  ✓ Cámara {i} seleccionada como C920")
            print(f"  ✓ Usar: --c920 {i} en los scripts, o pasar {i} como argumento posicional")

    if not found:
        print("\nNo se encontraron cámaras.")
        print("Verifica que estén conectadas y no bloqueadas por otra aplicación.")


if __name__ == "__main__":
    main()
