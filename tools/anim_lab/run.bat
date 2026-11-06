@echo off
rem Запуск стенда: run.bat  (Godot 4.7.2 в PATH как godot.exe, или set GODOT=C:\путь\Godot_v4.7.2-stable_win64.exe)
cd /d "%~dp0"
if "%GODOT%"=="" set GODOT=godot
if not exist ".godot\imported" "%GODOT%" --headless --path . --import
"%GODOT%" --path . %*
