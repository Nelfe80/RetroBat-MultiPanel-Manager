@echo off
setlocal EnableExtensions EnableDelayedExpansion
for %%R in ("%~dp0..\..\..\..\..") do set "RB_ROOT=%%~fR"
set "OUTDIR=%RB_ROOT%\plugins\api"

for %%i in ("%~dp0.") do set "eventName=%%~nxi"

set "API=http://127.0.0.1:1234"
set "OUTDIR=%~dp0..\..\..\..\plugins\api"
set "CURL=%SystemRoot%\System32\curl.exe"

set "SYS=%~1"
if not exist "%OUTDIR%" mkdir "%OUTDIR%" >nul 2>&1

(
  echo event=%eventName%
  echo %*
) > "%OUTDIR%\event.txt"

if "%SYS%"=="" exit /b 0

:: Update system
"%CURL%" -s -S "%API%/systems/%SYS%" > "%OUTDIR%\current-system.json"

:: Important: on invalide le jeu courant lors d’un system-selected
:: if exist "%OUTDIR%\current-game.json" del /Q "%OUTDIR%\current-game.json" >nul 2>&1

call :WRITE_STATE "%eventName%"
exit /b 0


:WRITE_STATE
set "EV=%~1"
set "STATE_TMP=%OUTDIR%\state.tmp"
set "STATE=%OUTDIR%\state.json"

(
  echo {
  echo   "meta": {
  echo     "updatedAt": "%date% %time%",
  echo     "event": "%EV%"
  echo   },
  echo   "current": {
  echo     "system":
  if exist "%OUTDIR%\current-system.json" (
    type "%OUTDIR%\current-system.json"
  ) else (
    echo null
  )
  echo   },
  echo   "modules": {
  echo     "runtime": "modules/runtime.json",
  echo     "hiscore": "modules/hiscore.json",
  echo     "retroachievements": "modules/ra.json",
  echo     "panel": "modules/panel.json",
  echo     "molding": "modules/molding.json",
  echo     "marquee": "modules/marquee.json"
  echo   }
  echo }
) > "%STATE_TMP%"

move /Y "%STATE_TMP%" "%STATE%" >nul
exit /b 0