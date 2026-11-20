@echo off
rem Pobiera tabele BMS (Stella, Satellite, Insane, Overjoy) do Assets\BMSTables
cd /d "%~dp0.."
python tools\update_bms_tables.py %*
pause
