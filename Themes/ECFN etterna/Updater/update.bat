@echo off
rem res extensa updater for Windows, started by the game
rem (DLMAN:BMSUpdateLaunch) right before it quits.
rem   update.bat <game pid> <installer .exe or -> <game folder>
rem Waits for the game to close, runs the new installer silently into the
rem same folder ("-": nothing, only a restart) and starts the game again.
rem Save, Songs and your other files stay: the installer only writes its own.
rem What happened goes to Logs\update.log.
setlocal
set "PID=%~1"
set "PKG=%~2"
set "ROOT=%~3"
if not exist "%ROOT%\Logs" mkdir "%ROOT%\Logs"
set "LOG=%ROOT%\Logs\update.log"
echo === %DATE% %TIME% update: %PKG% into %ROOT%>>"%LOG%"

rem the game has to be closed before its files can be swapped
set /a N=0
:wait
tasklist /FI "PID eq %PID%" 2>nul | find "%PID%" >nul
if errorlevel 1 goto closed
ping -n 2 127.0.0.1 >nul
set /a N+=1
if %N% LSS 120 goto wait
echo the game (pid %PID%) did not close, giving up>>"%LOG%"
exit /b 1
:closed

if "%PKG%"=="-" goto run
if exist "%ROOT%\.git" (
  echo %ROOT% is a git checkout, not updating it>>"%LOG%"
  goto run
)
rem /S: no questions, /D: this folder (must be last, without quotes)
start "" /wait "%PKG%" /S /D=%ROOT%
echo installer finished: %ERRORLEVEL%>>"%LOG%"
del "%PKG%" >nul 2>&1

:run
start "" /D "%ROOT%\Program" "%ROOT%\Program\Etterna.exe"
exit /b 0
