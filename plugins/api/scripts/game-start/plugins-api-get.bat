@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ==============================
:: Détection robuste RB_ROOT
:: ==============================
set "RB_ROOT="
set "P=%~dp0"

:UP
if exist "%P%roms\" set "RB_ROOT=%P%" & goto :FOUND
if exist "%P%RetroBat.exe" set "RB_ROOT=%P%" & goto :FOUND
for %%U in ("%P%..\") do set "P=%%~fU"
goto :UP

:FOUND
if "%RB_ROOT%"=="" exit /b 1

set "OUTDIR=%RB_ROOT%plugins\api"
if not exist "%OUTDIR%" mkdir "%OUTDIR%" >nul 2>&1

:: ==============================
:: Log brut
:: ==============================
(
  echo event=game-start
  echo %*
) > "%OUTDIR%\event.txt"

:: ==============================
:: Réécriture state.json
:: ==============================
call :WRITE_STATE "game-start"
exit /b 0


:WRITE_STATE
set "STATE_TMP=%OUTDIR%\state.tmp"
set "STATE=%OUTDIR%\state.json"

(
  echo {
  echo   "meta": {
  echo     "updatedAt": "%date% %time%",
  echo     "event": "game-start"
  echo   },
  echo   "current": {
  echo     "system":
  if exist "%OUTDIR%\current-system.json" (type "%OUTDIR%\current-system.json") else (echo null)
  echo     ,
  echo     "game":
  if exist "%OUTDIR%\current-game.json" (type "%OUTDIR%\current-game.json") else (echo null)
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