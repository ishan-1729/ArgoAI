@echo off
setlocal

cd /d "%~dp0"
set "REPO_DIR=%CD%"
set "GITOPS_DIR=%~dp0..\gitops-console-plugin"

echo [ArgoAI] Windows launcher
echo.

where git >nul 2>nul
if errorlevel 1 (
  echo [ArgoAI] Git is required. Install Git for Windows, then run this again.
  goto fail
)

where oc >nul 2>nul
if errorlevel 1 (
  echo [ArgoAI] OpenShift CLI ^(oc^) is required and was not found on PATH.
  goto fail
)

oc whoami >nul 2>nul
if errorlevel 1 (
  echo [ArgoAI] You are not logged into OpenShift.
  echo [ArgoAI] Run: oc login ^<cluster-api-url^>
  goto fail
)

if not exist "%GITOPS_DIR%\.git" (
  echo [ArgoAI] Cloning Red Hat GitOps console plugin next to ArgoAI...
  git clone https://github.com/redhat-developer/gitops-console-plugin.git "%GITOPS_DIR%"
  if errorlevel 1 goto fail
) else (
  echo [ArgoAI] GitOps console plugin checkout found.
)

where podman >nul 2>nul
if not errorlevel 1 (
  echo [ArgoAI] Starting Podman machine if needed...
  podman machine start >nul 2>nul
  for /f "delims=" %%M in ('podman machine list --format "{{.Name}}" 2^>nul') do podman machine start %%M >nul 2>nul
)

set "BASH_EXE="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
if not defined BASH_EXE if exist "%ProgramFiles%\Git\usr\bin\bash.exe" set "BASH_EXE=%ProgramFiles%\Git\usr\bin\bash.exe"
if not defined BASH_EXE for /f "delims=" %%B in ('where bash 2^>nul') do if not defined BASH_EXE set "BASH_EXE=%%B"

if not defined BASH_EXE (
  echo [ArgoAI] Git Bash is required. Install Git for Windows, then run this again.
  goto fail
)

echo.
echo [ArgoAI] Starting demo. Keep this window open; press Ctrl+C here to stop.
echo.
"%BASH_EXE%" -c "OPEN_UI=true bash ./setup-demo.sh"
if errorlevel 1 goto fail

exit /b 0

:fail
echo.
echo [ArgoAI] Startup failed. Fix the message above and run this file again.
pause
exit /b 1
