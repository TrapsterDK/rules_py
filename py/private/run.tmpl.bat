@echo off
setlocal EnableExtensions

set "SELF=%~f0"
set "SELF_ROOT=%~dpn0"
for %%I in ("%SELF%") do set "SELF_DIR=%%~dpI"
set "ORIG_RUNFILES_DIR=%RUNFILES_DIR%"
set "ORIG_RUNFILES_MANIFEST_FILE=%RUNFILES_MANIFEST_FILE%"
set "RUNFILES_DIR=%SELF%.runfiles"
set "RUNFILES_MANIFEST_FILE=%SELF%.runfiles\MANIFEST"

if not exist "%RUNFILES_DIR%\" set "RUNFILES_DIR=%SELF_ROOT%.runfiles"
if not exist "%RUNFILES_MANIFEST_FILE%" set "RUNFILES_MANIFEST_FILE=%SELF_ROOT%.runfiles\MANIFEST"
if not exist "%RUNFILES_MANIFEST_FILE%" set "RUNFILES_MANIFEST_FILE=%SELF%.runfiles_manifest"
if not exist "%RUNFILES_MANIFEST_FILE%" set "RUNFILES_MANIFEST_FILE=%SELF_ROOT%.runfiles_manifest"
if not exist "%RUNFILES_MANIFEST_FILE%" set "RUNFILES_MANIFEST_FILE=%SELF_ROOT%.exe.runfiles_manifest"
if not exist "%RUNFILES_DIR%\" if defined ORIG_RUNFILES_DIR set "RUNFILES_DIR=%ORIG_RUNFILES_DIR%"
if not exist "%RUNFILES_MANIFEST_FILE%" if defined ORIG_RUNFILES_MANIFEST_FILE set "RUNFILES_MANIFEST_FILE=%ORIG_RUNFILES_MANIFEST_FILE%"

set "VENV={{VENV}}"
set "ENTRYPOINT_RUNFILE={{ENTRYPOINT}}"

if not defined RUNFILES_DIR (
  echo ERROR: RUNFILES_DIR is not set and no runfiles directory was found for %SELF% 1>&2
  exit /b 1
)

set "VIRTUAL_ENV=%VENV:/=\%"
if not "%VIRTUAL_ENV:~1,1%"==":" set "VIRTUAL_ENV=%SELF_DIR%%VIRTUAL_ENV%"
set "ENTRYPOINT=%ENTRYPOINT_RUNFILE:/=\%"
for %%I in ("%SELF_DIR%..") do set "BIN_ROOT=%%~fI"
if exist "%BIN_ROOT%\%ENTRYPOINT%" set "ENTRYPOINT=%BIN_ROOT%\%ENTRYPOINT%"
if defined RUNFILES_DIR if exist "%RUNFILES_DIR%\%ENTRYPOINT%" set "ENTRYPOINT=%RUNFILES_DIR%\%ENTRYPOINT%"
if defined RUNFILES_MANIFEST_FILE if exist "%RUNFILES_MANIFEST_FILE%" (
  for /f "tokens=1,* delims= " %%A in ('%SystemRoot%\System32\findstr.exe /b /c:"%ENTRYPOINT_RUNFILE% " "%RUNFILES_MANIFEST_FILE%"') do set "ENTRYPOINT=%%B"
)
{{PYTHON_ENV}}

set "PATH=%VIRTUAL_ENV%\Scripts;%VIRTUAL_ENV%\bin;%PATH%"
set "PYTHONHOME="
set "PYTHONPATH="
if not exist "%VIRTUAL_ENV%\Scripts\python.exe" (
  echo ERROR: Expected venv interpreter at %VIRTUAL_ENV%\Scripts\python.exe 1>&2
  exit /b 1
)
if not exist "%ENTRYPOINT%" (
  echo ERROR: Expected entrypoint at %ENTRYPOINT% 1>&2
  exit /b 1
)
"%VIRTUAL_ENV%\Scripts\python.exe" {{INTERPRETER_FLAGS}} "%ENTRYPOINT%" %*
exit /b %ERRORLEVEL%

:rlocation
set "%~1="
if defined RUNFILES_DIR if exist "%RUNFILES_DIR%\%~2" (
  set "%~1=%RUNFILES_DIR%\%~2"
  exit /b 0
)
if defined RUNFILES_DIR if exist "%RUNFILES_DIR%\%~2.exe" (
  set "%~1=%RUNFILES_DIR%\%~2.exe"
  exit /b 0
)
if defined RUNFILES_MANIFEST_FILE if exist "%RUNFILES_MANIFEST_FILE%" (
  for /f "tokens=1,* delims= " %%A in ('%SystemRoot%\System32\findstr.exe /b /c:"%~2 " "%RUNFILES_MANIFEST_FILE%"') do set "%~1=%%B"
  if defined %~1 exit /b 0
  for /f "tokens=1,* delims= " %%A in ('%SystemRoot%\System32\findstr.exe /b /c:"%~2.exe " "%RUNFILES_MANIFEST_FILE%"') do set "%~1=%%B"
  if defined %~1 exit /b 0
)
echo ERROR: Failed to resolve runfile %~2 using RUNFILES_DIR=%RUNFILES_DIR% RUNFILES_MANIFEST_FILE=%RUNFILES_MANIFEST_FILE% 1>&2
exit /b 1
