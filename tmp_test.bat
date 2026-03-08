@echo off
setlocal EnableExtensions
call :foo
if errorlevel 1 exit /b %ERRORLEVEL%
echo ok
exit /b 0
:foo
exit /b 0
