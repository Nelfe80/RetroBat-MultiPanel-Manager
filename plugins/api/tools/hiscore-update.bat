@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ==========================================================
rem Paths
rem ==========================================================
for %%A in ("%~dp0..") do set "OUTDIR=%%~fA"
set "MODDIR=%OUTDIR%\modules"
if not exist "%MODDIR%" mkdir "%MODDIR%" >nul 2>&1

rem RetroBat root (OUTDIR = ...\plugins\api)
for %%A in ("%OUTDIR%\..\..") do set "ROOT=%%~fA"

set "GAME=%OUTDIR%\current-game.json"
set "DBG=%MODDIR%\hiscore-debug.log"
set "HISCORE_JSON=%MODDIR%\hiscore.json"

set "SAVES_NVRAM=%ROOT%\saves\mame\nvram"

rem hi2txt location (supports both layouts)
set "HITOOL=%ROOT%\plugins\api\tools\hi2txt\hi2txt.exe"
if not exist "%HITOOL%" set "HITOOL=%ROOT%\plugins\api\tools\hi2txt.exe"

>> "%DBG%" echo ==================================================
>> "%DBG%" echo %date% %time% - START (HISCORE)
>> "%DBG%" echo ROOT=%ROOT%
>> "%DBG%" echo HITOOL=%HITOOL%
>> "%DBG%" echo SAVES_NVRAM=%SAVES_NVRAM%

rem ==========================================================
rem Extract ROM + SYSTEM from current-game.json
rem ==========================================================
set "LINE="
for /f "usebackq delims=" %%L in (`findstr /i /c:"\"path\"" "%GAME%"`) do (
  set "LINE=%%L"
  goto :PARSE
)

:PARSE
if not defined LINE (
  call :WRITE_JSON "error_no_path" "" "" "" ""
  exit /b 1
)

set "ROMPATH=!LINE:*"path": "=!"
set "ROMPATH=!ROMPATH:",=!"
set "ROMPATH_WIN=!ROMPATH:/=\!"

for %%F in ("!ROMPATH_WIN!") do (
  set "ROMNAME=%%~nF"
  set "ROMDIR=%%~dpF"
)

set "ROMDIR_NOEND=!ROMDIR:~0,-1!"
for %%S in ("!ROMDIR_NOEND!") do set "SYSTEM=%%~nxS"

>> "%DBG%" echo ROMPATH=!ROMPATH!
>> "%DBG%" echo ROMNAME=!ROMNAME!
>> "%DBG%" echo SYSTEM=!SYSTEM!

rem ==========================================================
rem Detect nvram / saveram / eeprom (all inside ...\saves\mame\nvram\<rom>\)
rem ==========================================================
set "HSFILE="
set "HSTYPE="

if exist "%SAVES_NVRAM%\!ROMNAME!\nvram" (
  set "HSFILE=%SAVES_NVRAM%\!ROMNAME!\nvram"
  set "HSTYPE=nvram"
) else if exist "%SAVES_NVRAM%\!ROMNAME!\saveram" (
  set "HSFILE=%SAVES_NVRAM%\!ROMNAME!\saveram"
  set "HSTYPE=saveram"
) else if exist "%SAVES_NVRAM%\!ROMNAME!\eeprom" (
  set "HSFILE=%SAVES_NVRAM%\!ROMNAME!\eeprom"
  set "HSTYPE=eeprom"
)

>> "%DBG%" echo HSFILE=!HSFILE!
>> "%DBG%" echo HSTYPE=!HSTYPE!

if not defined HSFILE (
  call :WRITE_JSON "ok_no_hiscore_file" "!ROMPATH!" "!ROMNAME!" "" ""
  exit /b 0
)

if not exist "%HITOOL%" (
  call :WRITE_JSON "error_hi2txt_missing" "!ROMPATH!" "!ROMNAME!" "!HSFILE!" "!HSTYPE!"
  exit /b 2
)

rem ==========================================================
rem Run hi2txt
rem ==========================================================
set "OUTTXT=%MODDIR%\hiscore-!ROMNAME!.txt"
"%HITOOL%" -r "!HSFILE!" > "!OUTTXT!" 2>> "%DBG%"
if not "%ERRORLEVEL%"=="0" (
  call :WRITE_JSON "error_hi2txt_failed" "!ROMPATH!" "!ROMNAME!" "!HSFILE!" "!HSTYPE!"
  exit /b 3
)

rem ==========================================================
rem Build JSON (rank/score/name)
rem ==========================================================
set "TMPJSON=%HISCORE_JSON%.tmp"
> "!TMPJSON!" echo {
>>"!TMPJSON!" echo   "romName": "!ROMNAME!",
>>"!TMPJSON!" echo   "romPath": "!ROMPATH!",
>>"!TMPJSON!" echo   "system": "!SYSTEM!",
>>"!TMPJSON!" echo   "status": "ok_hiscore",
>>"!TMPJSON!" echo   "sourceType": "!HSTYPE!",
>>"!TMPJSON!" echo   "sourceFile": "!HSFILE!",
>>"!TMPJSON!" echo   "updatedAt": "%date% %time%",
>>"!TMPJSON!" echo   "scores": [

set "FIRST=1"
set "SKIPHEADER=1"

for /f "usebackq delims=" %%L in ("!OUTTXT!") do (
  if "!SKIPHEADER!"=="1" (
    set "SKIPHEADER=0"
  ) else (
    for /f "tokens=1-3 delims=|" %%A in ("%%L") do (
      if "!FIRST!"=="1" (set "FIRST=0") else (>>"!TMPJSON!" echo ,)
      call :JSON_ESCAPE "%%C" NAME_ESC
      >>"!TMPJSON!" echo     { "rank": %%A, "score": %%B, "name": "!NAME_ESC!" }
    )
  )
)

>>"!TMPJSON!" echo
>>"!TMPJSON!" echo   ]
>>"!TMPJSON!" echo }
move /Y "!TMPJSON!" "%HISCORE_JSON%" >nul

rem ==========================================================
rem Export FULL XML (columns + entries + extra fields)
rem ==========================================================
call :WRITE_XML_FULL "!SYSTEM!" "!ROMNAME!" "!OUTTXT!"
exit /b 0

rem ==========================================================
rem XML FULL EXPORT
rem ==========================================================
:WRITE_XML_FULL
rem %1=system %2=rom %3=path to hi2txt output (text)
set "XSYS=%~1"
set "XROM=%~2"
set "XTXT=%~3"

set "XMLDIR=%ROOT%\plugins\api\hiscore\%XSYS%"
if not exist "%XMLDIR%" mkdir "%XMLDIR%" >nul 2>&1
set "XMLFILE=%XMLDIR%\%XROM%.xml"

rem --- Read header line (columns)
set "HEADER="
for /f "usebackq delims=" %%H in ("%XTXT%") do (
  set "HEADER=%%H"
  goto :XML_GOT_HEADER
)

:XML_GOT_HEADER
if not defined HEADER (
  > "%XMLFILE%.tmp" echo ^<?xml version="1.0" encoding="utf-8"?^>
  >>"%XMLFILE%.tmp" echo ^<hiscore system="%XSYS%" rom="%XROM%" updatedAt="%date% %time%"^>
  >>"%XMLFILE%.tmp" echo   ^<scores /^>
  >>"%XMLFILE%.tmp" echo ^</hiscore^>
  move /Y "%XMLFILE%.tmp" "%XMLFILE%" >nul
  exit /b 0
)

rem Store column names COL1..COL20 based on HEADER split by |
for /f "tokens=1-20 delims=|" %%a in ("%HEADER%") do (
  set "COL1=%%a"
  set "COL2=%%b"
  set "COL3=%%c"
  set "COL4=%%d"
  set "COL5=%%e"
  set "COL6=%%f"
  set "COL7=%%g"
  set "COL8=%%h"
  set "COL9=%%i"
  set "COL10=%%j"
  set "COL11=%%k"
  set "COL12=%%l"
  set "COL13=%%m"
  set "COL14=%%n"
  set "COL15=%%o"
  set "COL16=%%p"
  set "COL17=%%q"
  set "COL18=%%r"
  set "COL19=%%s"
  set "COL20=%%t"
)

> "%XMLFILE%.tmp" echo ^<?xml version="1.0" encoding="utf-8"?^>
>>"%XMLFILE%.tmp" echo ^<hiscore system="%XSYS%" rom="%XROM%" updatedAt="%date% %time%"^>
>>"%XMLFILE%.tmp" echo   ^<columns^>
call :XML_COL "%COL1%" 1
call :XML_COL "%COL2%" 2
call :XML_COL "%COL3%" 3
call :XML_COL "%COL4%" 4
call :XML_COL "%COL5%" 5
call :XML_COL "%COL6%" 6
call :XML_COL "%COL7%" 7
call :XML_COL "%COL8%" 8
call :XML_COL "%COL9%" 9
call :XML_COL "%COL10%" 10
call :XML_COL "%COL11%" 11
call :XML_COL "%COL12%" 12
call :XML_COL "%COL13%" 13
call :XML_COL "%COL14%" 14
call :XML_COL "%COL15%" 15
call :XML_COL "%COL16%" 16
call :XML_COL "%COL17%" 17
call :XML_COL "%COL18%" 18
call :XML_COL "%COL19%" 19
call :XML_COL "%COL20%" 20
>>"%XMLFILE%.tmp" echo   ^</columns^>
>>"%XMLFILE%.tmp" echo   ^<scores^>

rem --- Iterate data lines (skip header)
set "SKIPHEADER=1"
for /f "usebackq delims=" %%L in ("%XTXT%") do (
  if "!SKIPHEADER!"=="1" (
    set "SKIPHEADER=0"
  ) else (
    for /f "tokens=1-20 delims=|" %%a in ("%%L") do (
      set "F1=%%a"
      set "F2=%%b"
      set "F3=%%c"
      set "F4=%%d"
      set "F5=%%e"
      set "F6=%%f"
      set "F7=%%g"
      set "F8=%%h"
      set "F9=%%i"
      set "F10=%%j"
      set "F11=%%k"
      set "F12=%%l"
      set "F13=%%m"
      set "F14=%%n"
      set "F15=%%o"
      set "F16=%%p"
      set "F17=%%q"
      set "F18=%%r"
      set "F19=%%s"
      set "F20=%%t"

      if defined F1 (
        call :XML_ESCAPE "!F1!" X_RANK
        call :XML_ESCAPE "!F2!" X_SCORE
        call :XML_ESCAPE "!F3!" X_NAME

        >>"%XMLFILE%.tmp" echo     ^<entry rank="!X_RANK!" score="!X_SCORE!" name="!X_NAME!"^>

        call :XML_FIELD "!COL4!"  "!F4!"
        call :XML_FIELD "!COL5!"  "!F5!"
        call :XML_FIELD "!COL6!"  "!F6!"
        call :XML_FIELD "!COL7!"  "!F7!"
        call :XML_FIELD "!COL8!"  "!F8!"
        call :XML_FIELD "!COL9!"  "!F9!"
        call :XML_FIELD "!COL10!" "!F10!"
        call :XML_FIELD "!COL11!" "!F11!"
        call :XML_FIELD "!COL12!" "!F12!"
        call :XML_FIELD "!COL13!" "!F13!"
        call :XML_FIELD "!COL14!" "!F14!"
        call :XML_FIELD "!COL15!" "!F15!"
        call :XML_FIELD "!COL16!" "!F16!"
        call :XML_FIELD "!COL17!" "!F17!"
        call :XML_FIELD "!COL18!" "!F18!"
        call :XML_FIELD "!COL19!" "!F19!"
        call :XML_FIELD "!COL20!" "!F20!"

        >>"%XMLFILE%.tmp" echo     ^</entry^>
      )
    )
  )
)

>>"%XMLFILE%.tmp" echo   ^</scores^>
>>"%XMLFILE%.tmp" echo ^</hiscore^>

move /Y "%XMLFILE%.tmp" "%XMLFILE%" >nul
exit /b 0

:XML_COL
rem %1=colname %2=index
set "CNAME=%~1"
set "CIDX=%~2"
if not defined CNAME exit /b 0
call :XML_ESCAPE "%CNAME%" C_ESC
>>"%XMLFILE%.tmp" echo     ^<col index="%CIDX%"^>!C_ESC!^</col^>
exit /b 0

:XML_FIELD
rem %1=key(colname) %2=value
set "K=%~1"
set "V=%~2"
if not defined K exit /b 0
if not defined V exit /b 0
call :XML_ESCAPE "%K%" K_ESC
call :XML_ESCAPE "%V%" V_ESC
>>"%XMLFILE%.tmp" echo       ^<field key="!K_ESC!"^>!V_ESC!^</field^>
exit /b 0

rem ==========================================================
rem HELPERS
rem ==========================================================
:WRITE_JSON
set "TMPJSON=%HISCORE_JSON%.tmp"
> "%TMPJSON%" echo {
>>"%TMPJSON%" echo   "romName": "%~3",
>>"%TMPJSON%" echo   "romPath": "%~2",
>>"%TMPJSON%" echo   "status": "%~1",
>>"%TMPJSON%" echo   "sourceType": "%~5",
>>"%TMPJSON%" echo   "sourceFile": "%~4",
>>"%TMPJSON%" echo   "updatedAt": "%date% %time%",
>>"%TMPJSON%" echo   "scores": []
>>"%TMPJSON%" echo }
move /Y "%TMPJSON%" "%HISCORE_JSON%" >nul
exit /b 0

:JSON_ESCAPE
rem Safe JSON escape (backslash + double quote)
setlocal DisableDelayedExpansion
set "s=%~1"
set "s=%s:\=\\%"
set "s=%s:"=\"%"
endlocal & set "%~2=%s%"
exit /b 0

:XML_ESCAPE
rem Safe XML escape: & < > " '
setlocal DisableDelayedExpansion
set "s=%~1"
set "s=%s:&=&amp;%"
set "s=%s:<=&lt;%"
set "s=%s:>=&gt;%"
set "s=%s:"=&quot;%"
set "s=%s:'=&apos;%"
endlocal & set "%~2=%s%"
exit /b 0