#!/usr/bin/env bash
# AgentDeck CI Quality Gates Verification Script (macOS / Linux)
set -euo pipefail

echo "=== Step 1/7: Flutter Pub Get ==="
flutter pub get

echo "=== Step 2/7: Dart Format Check ==="
dart format --output=none --set-exit-if-changed lib test tool

echo "=== Step 3/7: Flutter Analyze ==="
flutter analyze

echo "=== Step 4/7: Flutter Tests ==="
flutter test

echo "=== Step 5/7: Python Server Tests ==="
python3 -B -m unittest discover -s server/tests

echo "=== Step 6/7: M9 Push Integration Lab ==="
dart run tool/push_lab.dart

echo "=== Step 7/7: Git Diff & Whitespace Check ==="
git --no-pager diff --check

echo "========================================="
echo " ALL CI QUALITY GATES PASSED (100%)"
echo "========================================="
