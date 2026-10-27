# AgentDeck Pre-CI Local Verification Script (PowerShell / Windows)
# Strictly read-only gates before pushing or triggering CI workflows.

$ErrorActionPreference = "Stop"

$flutterCmd = if (Get-Command flutter -ErrorAction SilentlyContinue) { "flutter" } elseif (Test-Path "C:\Users\vszni\sdk\flutter\bin\flutter.bat") { "C:\Users\vszni\sdk\flutter\bin\flutter.bat" } else { "flutter" }
$dartCmd = if (Get-Command dart -ErrorAction SilentlyContinue) { "dart" } elseif (Test-Path "C:\Users\vszni\sdk\flutter\bin\dart.bat") { "C:\Users\vszni\sdk\flutter\bin\dart.bat" } else { "dart" }

Write-Host "=== Step 1/7: Flutter Pub Get ===" -ForegroundColor Cyan
& $flutterCmd pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== Step 2/7: Dart Format Check ===" -ForegroundColor Cyan
& $dartCmd format --output=none --set-exit-if-changed lib test tool
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== Step 3/7: Flutter Analyze ===" -ForegroundColor Cyan
& $flutterCmd analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== Step 4/7: Flutter Tests ===" -ForegroundColor Cyan
& $flutterCmd test
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== Step 5/7: Python Server Tests ===" -ForegroundColor Cyan
& python -B -m unittest discover -s server/tests
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== Step 6/7: M9 Push Integration Lab ===" -ForegroundColor Cyan
& $dartCmd run tool/push_lab.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== Step 7/7: Git Diff & Whitespace Check ===" -ForegroundColor Cyan
& git --no-pager diff --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=========================================" -ForegroundColor Green
Write-Host " ALL PRE-CI QUALITY GATES PASSED (100%)" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
