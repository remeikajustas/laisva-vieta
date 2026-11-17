@echo off
setlocal
cd /d "%~dp0"
set "GH=gh"
where gh >nul 2>nul || set "GH=C:\Program Files\GitHub CLI\gh.exe"
set "REPO=laisva-vieta"

set "LOGIN="
for /f "delims=" %%u in ('"%GH%" api user --jq .login') do set "LOGIN=%%u"
if "%LOGIN%"=="" (
  echo GitHub CLI neprisijungta. Paleisk: gh auth login
  pause
  exit /b 1
)
echo GitHub paskyra: %LOGIN%

if not exist .git git init -b main
git add -A
git commit -m "Operacija Laisva vieta" >nul 2>nul

"%GH%" repo view %LOGIN%/%REPO% >nul 2>nul
if errorlevel 1 (
  "%GH%" repo create %REPO% --public --source . --remote origin --push
) else (
  git remote get-url origin >nul 2>nul || git remote add origin https://github.com/%LOGIN%/%REPO%.git
  git push -u origin main
)
if errorlevel 1 (
  echo Ikelti nepavyko - ziurek klaida auksciau.
  pause
  exit /b 1
)

"%GH%" api repos/%LOGIN%/%REPO%/pages >nul 2>nul
if errorlevel 1 "%GH%" api -X POST repos/%LOGIN%/%REPO%/pages -f "source[branch]=main" -f "source[path]=/" >nul

echo.
echo Paruosta. Zaidimo adresas (pirma karta palauk 1-2 min.):
echo   https://%LOGIN%.github.io/%REPO%/
pause
