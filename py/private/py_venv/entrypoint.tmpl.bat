@echo off
setlocal EnableExtensions

if {{DEBUG}}==true echo on

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
if not exist "%RUNFILES_MANIFEST_FILE%" set "RUNFILES_MANIFEST_FILE=%RUNFILES_DIR%\MANIFEST"
if not exist "%RUNFILES_DIR%\" if defined ORIG_RUNFILES_DIR set "RUNFILES_DIR=%ORIG_RUNFILES_DIR%"
if not exist "%RUNFILES_MANIFEST_FILE%" if defined ORIG_RUNFILES_MANIFEST_FILE set "RUNFILES_MANIFEST_FILE=%ORIG_RUNFILES_MANIFEST_FILE%"

set "VENV={{VENV}}"
if not "%VENV:~1,1%"==":" set "VENV=%SELF_DIR%%VENV%"
set "PYTHONHOME="
set "PYTHONPATH="

if "{{MAIN}}"=="" goto run_plain

set "MAIN_RUNFILE={{MAIN}}"
set "MAIN=%MAIN_RUNFILE:/=\%"
if exist "%SELF_DIR%%MAIN%" set "MAIN=%SELF_DIR%%MAIN%"
if defined RUNFILES_DIR if exist "%RUNFILES_DIR%\%MAIN%" set "MAIN=%RUNFILES_DIR%\%MAIN%"
if defined RUNFILES_MANIFEST_FILE if exist "%RUNFILES_MANIFEST_FILE%" (
  for /f "tokens=1,* delims= " %%A in ('%SystemRoot%\System32\findstr.exe /b /c:"%MAIN_RUNFILE% " "%RUNFILES_MANIFEST_FILE%"') do set "MAIN=%%B"
)
if not exist "%MAIN%" (
  echo ERROR: Expected entrypoint at %MAIN% 1>&2
  exit /b 1
)
"%VENV%\Scripts\python.exe" {{INTERPRETER_FLAGS}} "%MAIN%" %*
exit /b %ERRORLEVEL%

:run_plain
"%VENV%\Scripts\python.exe" {{INTERPRETER_FLAGS}} %*
exit /b %ERRORLEVEL%
