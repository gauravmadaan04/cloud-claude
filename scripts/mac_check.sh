#!/bin/bash
# Builds, tests and packages Haven on this Mac.
#
#   scripts/mac_check.sh              everything: core tests, speed check, app tests, UI tests, release build, DMG
#   scripts/mac_check.sh --no-ui      skip the UI tests (they drive the mouse and keyboard for ~10 minutes)
#   scripts/mac_check.sh --bench ~    also time scanning and searching your own folders (read-only)
#
# Your files are never touched: the app and UI tests work on a sample folder they create in
# /private/tmp/haven-uitest-fixture, with their own settings. The UI tests quit a running Haven first.
set -euo pipefail
cd "$(dirname "$0")/.."

UI=1
BENCH_ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-ui) UI=0 ;;
    --bench) BENCH_ROOT="${2:-$HOME}"; shift ;;
    *) echo "Unknown option $1"; exit 2 ;;
  esac
  shift
done

step() { printf "\n\033[1m== %s\033[0m\n" "$*"; }
mkdir -p build
DD=build/dd

step "Tools"
command -v xcodebuild >/dev/null || { echo "Xcode is needed (App Store), then run: sudo xcode-select -s /Applications/Xcode.app"; exit 1; }
xcodebuild -version | head -1
if ! command -v xcodegen >/dev/null; then
  if command -v brew >/dev/null; then brew install xcodegen; else echo "Install XcodeGen (brew install xcodegen)"; exit 1; fi
fi

step "Core logic tests"
(cd Packages/HavenCore && swift test 2>&1 | grep -E "error:|Executed .* tests" | tail -3)

step "Speed check on 300,000 sample files"
(cd Packages/HavenCore && HAVEN_BENCH=1 swift test -c release --filter PerformanceTests 2>&1 | grep BENCH)

if [ -n "$BENCH_ROOT" ]; then
  step "Speed check on your folders (read-only)"
  (cd Packages/HavenCore && HAVEN_BENCH_ROOT="$BENCH_ROOT" swift test -c release --filter RealLibraryBenchmark 2>&1 | grep BENCH)
fi

step "Xcode project"
xcodegen generate >/dev/null && echo "Haven.xcodeproj generated"

step "Build app and tests"
set +e
xcodebuild build-for-testing -project Haven.xcodeproj -scheme Haven -destination 'platform=macOS' \
  -derivedDataPath "$DD" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES > build/build-debug.log 2>&1
set -e
if ! grep -q "TEST BUILD SUCCEEDED" build/build-debug.log; then
  grep -E "error:" build/build-debug.log | sort -u | head -60
  echo "Build failed (full log: build/build-debug.log)"
  exit 1
fi
echo "Build succeeded"

FAILED=0
step "App tests (OCR, PDFs, metadata, duplicates, trash and undo)"
set +e
xcodebuild test-without-building -project Haven.xcodeproj -scheme Haven -destination 'platform=macOS' \
  -derivedDataPath "$DD" -only-testing:HavenTests -resultBundlePath build/AppTests-$(date +%s).xcresult > build/app-tests.log 2>&1
[ $? -eq 0 ] || FAILED=1
set -e
grep -E "Test Case .*(passed|failed)|error:" build/app-tests.log | sed 's/^/  /' | tail -40

if [ "$UI" = 1 ]; then
  step "UI tests (hands off the mouse and keyboard until they finish)"
  osascript -e 'tell application "Haven" to quit' >/dev/null 2>&1 || true
  set +e
  xcodebuild test-without-building -project Haven.xcodeproj -scheme Haven -destination 'platform=macOS' \
    -derivedDataPath "$DD" -only-testing:HavenUITests -resultBundlePath build/UITests-$(date +%s).xcresult > build/ui-tests.log 2>&1
  [ $? -eq 0 ] || FAILED=1
  set -e
  grep -E "Test Case .*(passed|failed)|error:" build/ui-tests.log | sed 's/^/  /' | tail -40
  echo "Screenshots: /private/tmp/haven-shots"
fi

step "Release build (Apple silicon + Intel)"
set +e
xcodebuild -project Haven.xcodeproj -scheme Haven -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build/rel ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- build > build/build-release.log 2>&1
set -e
grep -q "BUILD SUCCEEDED" build/build-release.log || { grep -E "error:" build/build-release.log | head -40; exit 1; }
APP=build/rel/Build/Products/Release/Haven.app
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP" && lipo -info "$APP/Contents/MacOS/Haven"

step "DMG"
scripts/build_dmg.sh "$APP" build/Haven-1.0.0.dmg >/dev/null
hdiutil verify build/Haven-1.0.0.dmg >/dev/null && echo "build/Haven-1.0.0.dmg verified"
shasum -a 256 build/Haven-1.0.0.dmg

if [ "$FAILED" = 1 ]; then
  echo; echo "Some tests failed: see build/app-tests.log and build/ui-tests.log"
  exit 1
fi
echo; echo "All good. Install: open build/Haven-1.0.0.dmg and drag Haven to Applications (replace the old one)."
