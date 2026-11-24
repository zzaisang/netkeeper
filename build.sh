#!/bin/sh
# release 빌드 후 build/NetKeeper.app 번들 생성.
# Apple Development 인증서가 있으면 그것으로 서명해 재빌드해도 위치 권한·키체인 접근이 유지된다.
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/NetKeeper.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NetKeeper "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
IDENTITY=${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "built: $APP"
