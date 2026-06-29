@echo off
start "" "%~dp0venv\Scripts\python.exe" "%~dp0secuencia_detector_ipc_v4.py" 0
start "" "%~dp0venv\Scripts\python.exe" "%~dp0secuencia_hsv_visualizer.py" 1 --monitor 2
