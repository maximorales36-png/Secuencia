#!/usr/bin/env python3
"""
SECUENCIA - Detector de Postits (WebSocket)
Detecta postits de colores en tiempo real y envía posiciones vía WebSocket a Godot.
"""

import cv2
import numpy as np
import asyncio
import websockets
import json
import time
import sys

# ============================================================================
# CONFIGURACIÓN
# ============================================================================

CAPTURE_WIDTH = 640
CAPTURE_HEIGHT = 480
WEBSOCKET_HOST = "localhost"
WEBSOCKET_PORT = 8765
WEBSOCKET_URL = f"ws://{WEBSOCKET_HOST}:{WEBSOCKET_PORT}"
SEND_FREQUENCY = 10
SEND_INTERVAL = 1.0 / SEND_FREQUENCY
MIN_CONTOUR_AREA = 400
MAX_CONTOUR_AREA = 50000

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
    }
}

# ============================================================================
# VARIABLES GLOBALES
# ============================================================================

websocket_clients = set()
running = True

# ============================================================================
# FUNCIONES DE DETECCIÓN
# ============================================================================

def normalize_point(x, y, width, height):
    """Normaliza coordenadas a [0, 1]."""
    return (x / width, y / height)

def detect_color(frame, color_name, color_range):
    """Detecta un color específico en el frame."""
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
    """Dibuja círculos y etiquetas en las piezas detectadas."""
    for color_name, centers in detections.items():
        color_bgr = COLOR_RANGES[color_name]["bgr"]
        for cx, cy, contour in centers:
            cv2.drawContours(frame, [contour], 0, color_bgr, 2)
            cv2.circle(frame, (cx, cy), 5, color_bgr, -1)
            cv2.putText(frame, color_name, (cx + 10, cy - 10),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.4, color_bgr, 1)

def format_data(detections, width, height):
    """Formatea detecciones en dict para enviar vía WebSocket."""
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
# WEBSOCKET
# ============================================================================

async def send_to_all_clients(data):
    """Envía datos a todos los clientes."""
    global websocket_clients
    
    # Crear lista copia para iterar sin problemas
    clients_to_remove = []
    
    for client in list(websocket_clients):
        try:
            await client.send(json.dumps(data))
        except websockets.exceptions.ConnectionClosed:
            clients_to_remove.append(client)
        except Exception as e:
            print(f"[WebSocket] Error enviando a cliente: {e}")
            clients_to_remove.append(client)
    
    # Remover clientes desconectados
    for client in clients_to_remove:
        websocket_clients.discard(client)

async def websocket_server(websocket):
    """Handler para conexiones WebSocket."""
    global websocket_clients
    
    websocket_clients.add(websocket)
    print(f"[WebSocket] Cliente conectado. Total clientes: {len(websocket_clients)}")
    
    try:
        async for message in websocket:
            print(f"[WebSocket] Mensaje recibido: {message}")
    except websockets.exceptions.ConnectionClosed:
        print("[WebSocket] Cliente desconectado")
    finally:
        websocket_clients.discard(websocket)

async def video_capture_loop():
    """Loop principal de captura de video y envío de datos."""
    global running, websocket_clients
    
    print("[Video] Iniciando captura...")
    
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("[ERROR] No se pudo abrir la cámara.")
        return
    
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, CAPTURE_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAPTURE_HEIGHT)
    
    last_send_time = time.time()
    frame_count = 0
    
    try:
        while running:
            ret, frame = cap.read()
            if not ret:
                print("[ERROR] No se pudo leer frame de cámara.")
                break
            
            # Detectar todos los colores
            detections = {}
            for color_name in COLOR_RANGES.keys():
                detections[color_name] = detect_color(frame, color_name, COLOR_RANGES[color_name])
            
            # Dibujar en pantalla
            draw_detections(frame, detections)
            
            # Mostrar info
            cv2.putText(frame, f"Frame: {frame_count}", (10, 30),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200, 200, 200), 1)
            
            total_pieces = sum(len(centers) for centers in detections.values())
            cv2.putText(frame, f"Piezas: {total_pieces}", (10, 60),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200, 200, 200), 1)
            
            # Estado WebSocket
            ws_status = f"Conectado: {len(websocket_clients)}" if websocket_clients else "Esperando conexión"
            cv2.putText(frame, f"WebSocket: {ws_status}", (10, 90),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0) if websocket_clients else (0, 0, 255), 1)
            
            # Mostrar frame
            cv2.imshow("SECUENCIA - Detector", frame)
            
            # Enviar datos vía WebSocket cada SEND_INTERVAL
            current_time = time.time()
            if current_time - last_send_time >= SEND_INTERVAL:
                data = format_data(detections, CAPTURE_WIDTH, CAPTURE_HEIGHT)
                
                if websocket_clients:
                    await send_to_all_clients(data)
                    print(f"[{frame_count:05d}] Enviado: {len(data['piezas'])} piezas a {len(websocket_clients)} cliente(s)")
                
                last_send_time = current_time
            
            frame_count += 1
            
            # Salir con 'q' o 'Q'
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q') or key == ord('Q'):
                print("\n[OK] Saliendo...")
                running = False
                break
            
            # Yield para que otras tareas asyncio se ejecuten
            await asyncio.sleep(0.001)
    
    except KeyboardInterrupt:
        print("\n[OK] Interrumpido por usuario.")
        running = False
    
    finally:
        cap.release()
        cv2.destroyAllWindows()
        print("[OK] Recursos de video liberados.")

# ============================================================================
# MAIN
# ============================================================================

async def main():
    print("[SECUENCIA] Iniciando detector de postits (WebSocket)...")
    print(f"Resolución: {CAPTURE_WIDTH}x{CAPTURE_HEIGHT}")
    print(f"WebSocket: {WEBSOCKET_URL}")
    print(f"Frecuencia envío: {SEND_FREQUENCY} Hz")
    print("-" * 60)
    
    try:
        async with websockets.serve(websocket_server, WEBSOCKET_HOST, WEBSOCKET_PORT):
            print(f"[WebSocket] Servidor escuchando en {WEBSOCKET_URL}")
            await video_capture_loop()
    
    except OSError as e:
        print(f"[ERROR] No se pudo crear servidor WebSocket: {e}")
        print(f"Verifica que el puerto {WEBSOCKET_PORT} esté disponible")
        sys.exit(1)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[OK] Aplicación terminada.")
