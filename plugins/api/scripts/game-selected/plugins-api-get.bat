@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: =========================
:: Activer le debug ?
:: 0 = OFF
:: 1 = ON
:: =========================
set "DEBUG=0"

for %%i in ("%~dp0.") do set "eventName=%%~nxi"

set "API=http://127.0.0.1:1234"
set "OUTDIR=%~dp0..\..\..\..\plugins\api"
set "CURL=%SystemRoot%\System32\curl.exe"
set "DBG=%OUTDIR%\event-debug.txt"

set "SYS=%~1"
set "ROM=%~2"

if not exist "%OUTDIR%" mkdir "%OUTDIR%" >nul 2>&1

:: event.txt (brut)
(
  echo event=%eventName%
  echo %*
) > "%OUTDIR%\event.txt"

if "%SYS%"=="" exit /b 0
if "%ROM%"=="" exit /b 0

:: Normaliser les slashs
set "ROM=%ROM:\=/%"

if "%DEBUG%"=="1" call :LOGSAFE "ROM(norm)=%ROM%"

:: =========================
:: Calcul MD5 du path => ID
:: =========================
set "TMPSTR=%TEMP%\es_path_%RANDOM%.txt"
> "%TMPSTR%" <nul set /p "=%ROM%"

set "ID="
for /f "tokens=1" %%H in ('certutil -hashfile "%TMPSTR%" MD5 ^| findstr /r /i "^[0-9a-f][0-9a-f]"') do (
  set "ID=%%H"
  goto :GOTID
)

:GOTID
del "%TMPSTR%" >nul 2>&1

if "%ID%"=="" exit /b 0

if "%DEBUG%"=="1" call :LOGSAFE "MD5(id)=%ID%"

:: =========================
:: Update current-system
:: =========================
"%CURL%" -s -S "%API%/systems/%SYS%" > "%OUTDIR%\current-system.json"

if "%DEBUG%"=="1" call :LOGSAFE "curl systems exit=%ERRORLEVEL%"

:: =========================
:: Update current-game
:: =========================
"%CURL%" -s -S "%API%/systems/%SYS%/games/%ID%" > "%OUTDIR%\current-game.json"

if "%DEBUG%"=="1" call :LOGSAFE "curl game exit=%ERRORLEVEL%"
if "%DEBUG%"=="1" call :LOGSAFE "OK: current-game updated"

call :WRITE_STATE "%eventName%"

exit /b 0


:LOGSAFE
set "S=%~1"
set "S=%S:^=^^%"
set "S=%S:&=^&%"
set "S=%S:|=^|%"
set "S=%S:<=^<%"
set "S=%S:>=^>%"
>> "%DBG%" echo %S%
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
  echo     ,
  echo     "game":
  if exist "%OUTDIR%\current-game.json" (
    type "%OUTDIR%\current-game.json"
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