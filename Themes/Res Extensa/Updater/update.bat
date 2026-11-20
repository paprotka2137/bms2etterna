@echo off
rem res extensa updater for Windows, started by the game
rem (DLMAN:BMSUpdateLaunch) right before it quits.
rem   update.bat <game pid> <installer .exe or -> <game folder>
rem Waits for the game to close, opens the new installer for the same
rem folder ("-": nothing, only a restart) and starts the game again.
rem Save, Songs and your other files stay: the installer only writes its own.
rem What happened goes to Logs\update.log.
setlocal EnableExtensions
set "PID=%~1"
set "PKG=%~2"
set "ROOT=%~3"

rem The game starts this script without a window, from inside the game
rem folder. Run a copy from TEMP in a window you can see instead: the
rem installer may replace or remove this file while it runs.
if /i "%~4"=="visible" goto main
set "COPY=%TEMP%\res-extensa-update.bat"
copy /y "%~f0" "%COPY%" >nul 2>&1
if errorlevel 1 set "COPY=%~f0"
start "res extensa update" "%COPY%" "%PID%" "%PKG%" "%ROOT%" visible
exit /b 0

:main
title res extensa update
if not exist "%ROOT%\Logs" mkdir "%ROOT%\Logs"
set "LOG=%ROOT%\Logs\update.log"
call :say === %DATE% %TIME% update: "%PKG%" into "%ROOT%"

call :say Waiting for the game to close...
ping -n 3 127.0.0.1 >nul
set /a N=0
:wait
tasklist /FI "PID eq %PID%" /NH 2>nul | find " %PID% " >nul
if errorlevel 1 goto closed
ping -n 2 127.0.0.1 >nul
set /a N+=1
rem a game window that's gone but a process that stays (a stuck thread on
rem exit) would block the update forever: end it after 20 seconds
if %N%==20 call :say The game is still running after closing, ending it.
if %N%==20 taskkill /PID %PID% /F >nul 2>&1
if %N% LSS 60 goto wait
call :say The game did not close, update stopped. Close it in Task Manager and run the installer from the release page.
pause
exit /b 1

:closed
if "%PKG%"=="-" goto run
if exist "%ROOT%\.git" goto checkout
if not exist "%PKG%" goto nopkg
call :say Opening the installer: "%PKG%"
call :say The folder is already filled in, click Install. Save and Songs stay.
rem /D: install into this game folder (must be last, without quotes)
start "" /wait "%PKG%" /D=%ROOT%
set "RC=%ERRORLEVEL%"
call :say Installer finished with code %RC%.
if not "%RC%"=="0" goto failed
del "%PKG%" >nul 2>&1
call :say Updated.
goto run

:checkout
call :say "%ROOT%" is a git checkout, not updating it.
goto run

:nopkg
call :say The downloaded installer is missing: "%PKG%"
pause
goto run

:failed
call :say The installer did not finish, starting the old version.
pause

:run
call :say Starting the game.
start "" /D "%ROOT%\Program" "%ROOT%\Program\Etterna.exe"
exit /b 0

:say
echo %*
>>"%LOG%" echo %*
exit /b 0
