@echo off
start "" "%~dp0venv\Scripts\python.exe" "%~dp0secuencia_detector_ipc_v4.py" 0
timeout /t 2 /nobreak >nul
start "" "%~dp0venv\Scripts\python.exe" "%~dp0secuencia_hsv_visualizer.py" 1 --monitor 2 --fill
REM Para debuggear errores del visualizer, ejecutalo solo con:
REM "%~dp0venv\Scripts\python.exe" "%~dp0secuencia_hsv_visualizer.py" 1 --monitor 2 --fill
