#!/bin/sh
# Mac App Store용 아카이브 생성 → build/NetKeeper.xcarchive
# SwiftPM 프로젝트라 xcodebuild archive 대신 .xcarchive 를 직접 만들고,
# 배포 서명은 scripts/appstore-upload.sh 의 xcodebuild -exportArchive(클라우드 서명)가 맡는다.
#   - APPSTORE 플래그: 샌드박스에서 못 쓰는 기능(Instant Hotspot, macOS 암호 가져오기) 제외
#   - Universal(arm64 + x86_64) 바이너리
#   - Apple Development 인증서로 샌드박스 entitlements 를 넣어 개발 서명 (export 때 배포 서명으로 교체됨)
set -e
cd "$(dirname "$0")/.."

IDENTITY=${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}
[ -n "$IDENTITY" ] || { echo "ERROR: Apple Development 인증서 없음" >&2; exit 1; }
TEAM=$(security find-certificate -c "$IDENTITY" -p | openssl x509 -noout -subject | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p')

swift build -c release --arch arm64 --arch x86_64 -Xswiftc -DAPPSTORE --build-path .build/appstore
BIN=.build/appstore/apple/Products/Release/NetKeeper

ARCHIVE=build/NetKeeper.xcarchive
APP=$ARCHIVE/Products/Applications/NetKeeper.app
rm -rf "$ARCHIVE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ARCHIVE/dSYMs"
cp "$BIN" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
cp -R Resources/ "$APP/Contents/Resources/"
codesign --force --options runtime --entitlements appstore/NetKeeper.entitlements --sign "$IDENTITY" "$APP"

python3 - "$ARCHIVE" "$APP" "$IDENTITY" "$TEAM" <<'PY'
import datetime, plistlib, sys
archive, app, identity, team = sys.argv[1:]
info = plistlib.load(open(f"{app}/Contents/Info.plist", "rb"))
plistlib.dump({
    "ApplicationProperties": {
        "ApplicationPath": "Applications/NetKeeper.app",
        "Architectures": ["arm64", "x86_64"],
        "CFBundleIdentifier": info["CFBundleIdentifier"],
        "CFBundleShortVersionString": info["CFBundleShortVersionString"],
        "CFBundleVersion": info["CFBundleVersion"],
        "SigningIdentity": identity,
        "Team": team,
    },
    "ArchiveVersion": 2,
    "CreationDate": datetime.datetime.now(datetime.timezone.utc),
    "Name": "NetKeeper",
    "SchemeName": "NetKeeper",
}, open(f"{archive}/Info.plist", "wb"))
print(f"archived: {archive} ({info['CFBundleShortVersionString']} build {info['CFBundleVersion']}, team {team})")
PY
