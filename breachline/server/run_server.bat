@echo off
REM Dedicated Breachline server. Set GODOT to your Godot 4.4 executable if it is not on PATH.
cd /d "%~dp0\.."
if "%GODOT%"=="" set GODOT=godot
"%GODOT%" --headless --path . -- --server %*
