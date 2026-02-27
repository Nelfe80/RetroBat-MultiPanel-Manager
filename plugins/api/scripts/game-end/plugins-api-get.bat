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
set "TOOLDIR=%OUTDIR%\tools"

if not exist "%OUTDIR%" mkdir "%OUTDIR%" >nul 2>&1
if not exist "%OUTDIR%\modules" mkdir "%OUTDIR%\modules" >nul 2>&1

:: ==============================
:: Debug preuve d'exécution
:: ==============================
::echo CALLED game-end %date% %time% > "%OUTDIR%\modules\_called_game-end.txt"
::echo RB_ROOT=%RB_ROOT% > "%OUTDIR%\modules\_game-end_paths.txt"
::echo OUTDIR=%OUTDIR% >> "%OUTDIR%\modules\_game-end_paths.txt"
::echo TOOLDIR=%TOOLDIR% >> "%OUTDIR%\modules\_game-end_paths.txt"

:: ==============================
:: Log brut de l'event
:: (évite echo %* car & peut casser)
:: ==============================
set "A1=%~1"
set "A2=%~2"
set "A3=%~3"
(
  echo event=game-end
  echo %A1% %A2% %A3%
) > "%OUTDIR%\event.txt"

:: ==============================
:: Vérif current-game présent ?
:: ==============================
::if exist "%OUTDIR%\current-game.json" (
::  echo current-game exists > "%OUTDIR%\modules\_game_end_has_current_game.json"
::) else (
::  echo current-game missing > "%OUTDIR%\modules\_game_end_has_current_game.json"
::)

:: ==============================
:: Pause pour laisser NVRAM écrire
:: ==============================
ping 127.0.0.1 -n 2 >nul

:: ==============================
:: Mise à jour Hiscore
:: ==============================
if exist "%TOOLDIR%\hiscore-update.bat" (
  call "%TOOLDIR%\hiscore-update.bat"
) else (
  echo hiscore-update.bat missing > "%OUTDIR%\modules\_hiscore_missing.txt"
)

:: ==============================
:: Réécriture state.json (Option B)
:: ==============================
call :WRITE_STATE "game-end"
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