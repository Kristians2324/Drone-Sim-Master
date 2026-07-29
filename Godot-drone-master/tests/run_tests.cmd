@echo off
setlocal

set "GODOT_EXE="
if exist "%USERPROFILE%\Desktop\R2\Godot_v4.6.2-stable_win64_console.exe" set "GODOT_EXE=%USERPROFILE%\Desktop\R2\Godot_v4.6.2-stable_win64_console.exe"
if "%GODOT_EXE%"=="" if exist "%USERPROFILE%\Desktop\R2\Godot_v4.6.2-stable_win64.exe" set "GODOT_EXE=%USERPROFILE%\Desktop\R2\Godot_v4.6.2-stable_win64.exe"
if "%GODOT_EXE%"=="" if exist "%USERPROFILE%\Desktop\Godot\Godot_v4.6.2-stable_win64.exe" set "GODOT_EXE=%USERPROFILE%\Desktop\Godot\Godot_v4.6.2-stable_win64.exe"

if "%GODOT_EXE%"=="" (
	echo Could not find Godot executable.
	pause
	exit /b 1
)

pushd "%~dp0\.."
set "LOG=%~dp0test_output.txt"

echo Running Drone Sim tests with: %GODOT_EXE%
echo.

"%GODOT_EXE%" --headless --path . --xr-mode off --script res://tests/test_runner.gd > "%LOG%" 2>&1

type "%LOG%"

findstr /C:"ALL TESTS PASSED WITH 0 ERRORS" "%LOG%" >nul 2>&1
if %ERRORLEVEL%==0 (
	set "EXITCODE=0"
) else (
	set "EXITCODE=1"
)

echo.
if "%EXITCODE%"=="0" (
	echo [ALL TESTS PASSED] Exit code: 0
) else (
	echo [TESTS FAILED] Exit code: %EXITCODE%
)

popd
if "%1"=="--pause" pause
exit /b %EXITCODE%