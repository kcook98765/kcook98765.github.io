@echo off
setlocal ENABLEDELAYEDEXPANSION

REM ========= EDITABLE MINIMUMS =========
set "SUBMODULE_PATH=repo\plugin.video.librarygenie"
set "GENERATOR=_repo_generator.py"
set "BRANCH=master"
REM =====================================

if "%~1"=="" (
  echo Usage: %~nx0 ^<LibraryGenieVersion^>
  echo Example: %~nx0 0.8.8
  exit /b 1
)
set "LG_VERSION=%~1"

REM --- sanity checks (local only; no other repo references) ---
where git >nul 2>&1 || (echo [ERROR] git not found in PATH & exit /b 1)
where python >nul 2>&1 || (echo [ERROR] python not found in PATH & exit /b 1)
if not exist "%GENERATOR%" (echo [ERROR] %GENERATOR% not found. Run from this repo's root. & exit /b 1)
if not exist "repo" (echo [ERROR] 'repo\' folder missing. Run from this repo's root. & exit /b 1)

REM --- auto-detect Kodi repository add-on dir, id, version from addon.xml ---
for /d %%D in (repo\repository.*) do (
  set "REPO_ADDON_DIR=%%D"
  goto :foundRepoDir
)
:foundRepoDir
if not defined REPO_ADDON_DIR (
  echo [ERROR] Could not find a folder like repo\repository.*
  exit /b 1
)

for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "(Select-Xml -Path '%REPO_ADDON_DIR%\addon.xml' -XPath '/addon').Node.id"`) do set "REPO_ADDON_ID=%%I"
for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "(Select-Xml -Path '%REPO_ADDON_DIR%\addon.xml' -XPath '/addon').Node.version"`) do set "REPO_ADDON_VERSION=%%V"

if not defined REPO_ADDON_ID (echo [ERROR] Could not read repo add-on ID from %REPO_ADDON_DIR%\addon.xml & exit /b 1)
if not defined REPO_ADDON_VERSION (echo [ERROR] Could not read repo add-on version from %REPO_ADDON_DIR%\addon.xml & exit /b 1)

echo [INFO] Kodi repo add-on : %REPO_ADDON_ID% (%REPO_ADDON_VERSION%)
echo [INFO] Submodule path   : %SUBMODULE_PATH%
echo [INFO] Target version   : %LG_VERSION%
echo [INFO] Branch           : %BRANCH%
echo.

REM --- 1) fetch + rebase this repo on its remote ---
echo [STEP] git fetch origin
git fetch origin || (echo [ERROR] git fetch failed & exit /b 1)

echo [STEP] git pull --rebase origin %BRANCH%
git pull --rebase origin %BRANCH%
if errorlevel 1 (
  echo [WARN] Rebase reported conflicts. Resolve, then run:
  echo        git add [files] ^&^& git rebase --continue
  exit /b 1
)

REM --- 2) update only the LibraryGenie submodule (local repo only) ---
if exist "%SUBMODULE_PATH%\.git" (
  echo [STEP] git submodule update --remote --init "%SUBMODULE_PATH%"
  git submodule update --remote --init "%SUBMODULE_PATH%" || (echo [ERROR] submodule update failed & exit /b 1)

  echo [STEP] Commit submodule pointer bump (if changed)
  git add "%SUBMODULE_PATH%"
  git commit -m "Update LibraryGenie submodule to %LG_VERSION%"
  if errorlevel 1 echo [INFO] No submodule pointer change to commit.
) else (
  echo [INFO] Submodule not found at %SUBMODULE_PATH%. Assuming code is vendored directly in repo\ .
)

REM --- 3) build zips & index locally ---
echo [STEP] python %GENERATOR%
python "%GENERATOR%" || (echo [ERROR] generator failed & exit /b 1)

REM --- 4) verify expected addon zip exists (local) ---
set "LG_ZIP=repo\zips\plugin.video.librarygenie\plugin.video.librarygenie-%LG_VERSION%.zip"
if not exist "%LG_ZIP%" (
  echo [ERROR] Expected zip not found: %LG_ZIP%
  echo         Make sure plugin.video.librarygenie/addon.xml is bumped to %LG_VERSION% and pushed in the submodule repo.
  exit /b 1
) else (
  for %%A in ("%LG_ZIP%") do echo [OK] Built %%~nxA (%%~zA bytes)
)

REM --- 5) copy repo zip to root (for easy browser install) ---
set "REPO_ZIP_SRC=repo\zips\%REPO_ADDON_ID%\%REPO_ADDON_ID%-%REPO_ADDON_VERSION%.zip"
set "REPO_ZIP_DST=%REPO_ADDON_ID%-%REPO_ADDON_VERSION%.zip"
if exist "%REPO_ZIP_SRC%" (
  copy /Y "%REPO_ZIP_SRC%" "%REPO_ZIP_DST%" >nul
  if errorlevel 1 (echo [WARN] Could not copy %REPO_ZIP_SRC% to root) else echo [OK] Copied %REPO_ZIP_DST% to repo root
) else (
  echo [WARN] Repo zip not found at %REPO_ZIP_SRC%. Continuing anyway.
)

REM --- 6) commit build artifacts & push from this repo ---
echo [STEP] Commit build artifacts
git add .
git commit -m "Publish LibraryGenie %LG_VERSION%; rebuild index"
if errorlevel 1 echo [INFO] Nothing new to commit.

echo [STEP] Push to origin/%BRANCH%
git push
if errorlevel 1 (
  echo [WARN] Push rejected. Trying fetch+rebase then re-push...
  git fetch origin && git pull --rebase origin %BRANCH%
  if errorlevel 1 (
    echo [ERROR] Rebase failed. Resolve conflicts, then:
    echo        git add [files] ^&^& git rebase --continue ^&^& git push
    exit /b 1
  )
  git push || (echo [ERROR] Push failed again. Resolve and retry. & exit /b 1)
)

echo.
echo [DONE] Published LibraryGenie %LG_VERSION% from this repo.
echo [TEST] Open these in a browser:
echo        raw ^> repo/zips/addons.xml
echo        raw ^> repo/zips/addons.xml.md5
echo        pages ^> /%REPO_ADDON_ID%-%REPO_ADDON_VERSION%.zip
echo.
exit /b 0
