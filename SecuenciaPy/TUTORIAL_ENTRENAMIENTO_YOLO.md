# Tutorial de Entrenamiento YOLO para SECUENCIA

## Requisitos

- Python 3.10+
- GPU NVIDIA con CUDA 12+ recomendada
- ~2 GB de espacio en disco

## Instalación

```bash
cd SecuenciaPy
pip install -r requirements_v3.txt
```

## 1. Captura de Fotos

Con el detector v3 corriendo en modo HSV:

```bash
python secuencia_detector_ipc_v3.py --mode hsv
```

Coloca cada pieza 3D (cubo, pirámide, semi-esfera, hexágono, cono) sobre la mesa proyectada y captura fotos del frame rectificado. Puedes usar cualquier herramienta de captura (ej. `cv2.imwrite()` desde un script aparte, o simplemente Print Screen).

Recomendación:
- ~100 fotos por pieza
- Variar posición (x, y) y rotación
- Variar iluminación (sombras, brillos)
- Incluir fondo sin piezas (negativas)

Guardar en carpetas separadas:
```
capturas/
  red/
  pink/
  green/
  blue/
  violet/
```

## 2. Etiquetado con Roboflow

1. Crear cuenta en [Roboflow](https://roboflow.com)
2. Crear nuevo proyecto → Object Detection
3. Subir las fotos
4. Etiquetar cada pieza con su color (red, pink, green, blue, violet)
   - Dibujar bounding box ajustado alrededor de cada pieza
5. Generar dataset → Apply Preprocessing y Augmentation:
   - Preprocessing: Auto-orient, Resize (640x640)
   - Augmentation: Rotate (-15° a +15°), Brightness (-10% a +10%), Blur (2px), Noise (2px)
6. Exportar → formato **YOLOv8** (es el estándar Ultralytics, funciona con v8/v9/v10/v11/YOLO26) → descargar .zip

## 3. Entrenamiento

```bash
# Descomprimir dataset
unzip roboflow_dataset.zip -d datasets/secuencia

# Entrenar YOLO26n
yolo train model=yolo26n.pt data=datasets/secuencia/data.yaml epochs=100 imgsz=640 batch=16 device=0
```

Parámetros recomendados:
- `epochs`: 100-200 (más si hay pocos datos)
- `batch`: 16-32 (según VRAM)
- `device`: 0 (GPU), "cpu" si no hay GPU
- `patience`: 20 (early stopping)

## 4. Exportar Modelo

```bash
# El mejor checkpoint se guarda en runs/detect/train/weights/best.pt
cp runs/detect/train/weights/best.pt modelos/yolo26n.pt
```

## 5. Verificar

```bash
python secuencia_detector_ipc_v3.py --mode yolo
```

Presionar **T** para toggle entre HSV y YOLO en runtime.
