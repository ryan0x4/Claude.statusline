@echo off
setlocal

:: Locate statusline.sh in the same directory as this .cmd file
set "SCRIPT_DIR=%~dp0"
set "SH_SCRIPT=%SCRIPT_DIR%statusline.sh"

:: 1. Check if bash is available in PATH
where bash >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    bash "%SH_SCRIPT%" %*
    goto :end
)

:: 2. Check 64-bit Git for Windows installation
if exist "%ProgramFiles%\Git\bin\bash.exe" (
    "%ProgramFiles%\Git\bin\bash.exe" "%SH_SCRIPT%" %*
    goto :end
)

:: 3. Check LocalAppData Git for Windows (User-level install)
if exist "%LocalAppData%\Programs\Git\bin\bash.exe" (
    "%LocalAppData%\Programs\Git\bin\bash.exe" "%SH_SCRIPT%" %*
    goto :end
)

:: 4. Check 32-bit Git for Windows installation
if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" (
    "%ProgramFiles(x86)%\Git\bin\bash.exe" "%SH_SCRIPT%" %*
    goto :end
)

:: 5. Check Git usr\bin\bash.exe fallback
if exist "%ProgramFiles%\Git\usr\bin\bash.exe" (
    "%ProgramFiles%\Git\usr\bin\bash.exe" "%SH_SCRIPT%" %*
    goto :end
)

echo [AI] Git Bash is required to run lite-hud on Windows. Please install Git for Windows.
exit /b 1

:end
exit /b %ERRORLEVEL%
