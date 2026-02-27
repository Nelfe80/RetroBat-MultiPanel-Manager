@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SYS=%~1"
set "ROM=%~2"
if "%SYS%"=="" exit /b 1
if "%ROM%"=="" exit /b 1

:: ==============================
:: Détection RB_ROOT + anti-boucle
:: ==============================
set "RB_ROOT="
set "P=%~dp0"
set /a UPN=0

:UP
set /a UPN+=1
if %UPN% GTR 25 exit /b 2

if exist "%P%roms\" set "RB_ROOT=%P%" & goto :FOUND
if exist "%P%RetroBat.exe" set "RB_ROOT=%P%" & goto :FOUND
for %%U in ("%P%..\") do set "P=%%~fU"
goto :UP

:FOUND
if "%RB_ROOT%"=="" exit /b 2

set "OUTDIR=%RB_ROOT%plugins\api"
set "MODDIR=%OUTDIR%\modules"
if not exist "%MODDIR%" mkdir "%MODDIR%" >nul 2>&1

set "GAMELIST=%RB_ROOT%roms\%SYS%\gamelist.xml"
set "RUNTIME=%MODDIR%\runtime.json"
set "DBG=%MODDIR%\runtime-debug.log"

for %%F in ("%ROM%") do set "ROMFILE=%%~nxF"

>>"%DBG%" echo ==================================================
>>"%DBG%" echo %date% %time% - START runtime-update (PURE BAT PIPE)
>>"%DBG%" echo SYS="%SYS%" ROM="%ROM%" ROMFILE="%ROMFILE%"
>>"%DBG%" echo RB_ROOT="%RB_ROOT%"
>>"%DBG%" echo GAMELIST="%GAMELIST%"
>>"%DBG%" echo RUNTIME="%RUNTIME%"
>>"%DBG%" echo [STEP] header OK

:: ==============================
:: Check gamelist exists (sans parenthèses)
:: ==============================
>>"%DBG%" echo [STEP] check gamelist exist begin
if not exist "%GAMELIST%" goto :NO_GAMELIST
>>"%DBG%" echo [STEP] check gamelist exist OK

:: ==============================
:: Parsing via PIPE (évite for /f sur fichier)
:: On ne garde que les lignes utiles.
:: ==============================
set "EMU="
set "CORE="
set "FOUND=0"
set "IN_GAME=0"
set "BREAK=0"

>>"%DBG%" echo [STEP] parse begin (type^|findstr)

for /f "usebackq delims=" %%L in (`
  cmd /v:on /c ^"type "%GAMELIST%" ^| findstr /i /r "<game|</game>|<path>|<emulator>|<core>"^"
`) do (
  if "!BREAK!"=="1" (
    rem ignore
  ) else (
    set "L=%%L"

    :: Entrée bloc <game ...> (ignore <gameList>)
    echo(!L! | findstr /i "<game" >nul && (
      echo(!L! | findstr /i "<gameList" >nul || (
        set "IN_GAME=1"
        set "FOUND=0"
      )
    )

    if "!IN_GAME!"=="1" (
      echo(!L! | findstr /i "<path>" >nul && (
        echo(!L! | findstr /i "%ROMFILE%" >nul && (
          set "FOUND=1"
          >>"%DBG%" echo [GL] MATCH path: !L!
        )
      )

      if "!FOUND!"=="1" (
        echo(!L! | findstr /i "<emulator>" >nul && (
          set "TMP=!L!"
          set "TMP=!TMP:*<emulator>=!"
          set "TMP=!TMP:</emulator>=!"
          set "EMU=!TMP!"
          >>"%DBG%" echo [GL] emulator="!EMU!"
        )
        echo(!L! | findstr /i "<core>" >nul && (
          set "TMP=!L!"
          set "TMP=!TMP:*<core>=!"
          set "TMP=!TMP:</core>=!"
          set "CORE=!TMP!"
          >>"%DBG%" echo [GL] core="!CORE!"
        )
      )

      echo(!L! | findstr /i "</game>" >nul && (
        if "!FOUND!"=="1" set "BREAK=1"
        set "IN_GAME=0"
      )
    )
  )
)

>>"%DBG%" echo [STEP] parse end
>>"%DBG%" echo parsed: EMU="%EMU%" CORE="%CORE%"

if "%EMU%"=="" (
  set "EMU=auto"
  >>"%DBG%" echo [WARN] no emulator found -> auto
)
if "%CORE%"=="" set "CORE=null"

>>"%DBG%" echo [STEP] write begin
call :WRITE_RUNTIME "%SYS%" "%ROMFILE%" "%EMU%" "%CORE%" "gamelist"
set "EC=%errorlevel%"
>>"%DBG%" echo [STEP] write end errorlevel=%EC%
>>"%DBG%" echo %date% %time% - FINISHED
exit /b %EC%


:NO_GAMELIST
>>"%DBG%" echo [WARN] gamelist missing -> write auto
call :WRITE_RUNTIME "%SYS%" "%ROMFILE%" "auto" "null" "gamelist_missing"
>>"%DBG%" echo %date% %time% - FINISHED (gamelist_missing)
exit /b 0


:WRITE_RUNTIME
set "SYSX=%~1"
set "ROMX=%~2"
set "EMUX=%~3"
set "COREX=%~4"
set "SRCX=%~5"

set "TMPFILE=%RUNTIME%.tmp"

(
  echo {
  echo   "system": "%SYSX%",
  echo   "romFile": "%ROMX%",
  echo   "emulator": "%EMUX%",
  if /i "%COREX%"=="null" (
    echo   "core": null,
  ) else (
    echo   "core": "%COREX%",
  )
  echo   "source": "%SRCX%",
  echo   "updatedAt": "%date% %time%"
  echo }
) > "%TMPFILE%"

if not exist "%TMPFILE%" exit /b 10

move /Y "%TMPFILE%" "%RUNTIME%" >nul
if errorlevel 1 (
  :: fallback si move échoue (lock)
  copy /Y "%TMPFILE%" "%RUNTIME%" >nul
  del /Q "%TMPFILE%" >nul 2>&1
)
exit /b 0