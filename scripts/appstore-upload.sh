#!/bin/sh
# build/NetKeeper.xcarchive 를 App Store Connect API 키로 클라우드 서명해 업로드한다.
#   scripts/appstore-upload.sh           # 업로드
#   scripts/appstore-upload.sh --export  # 업로드 없이 서명된 .pkg 만 만들어 확인 (build/export/)
# 키: ~/.appstoreconnect/netkeeper.env (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, ASC_TEAM_ID).
# .p8 은 경로로만 넘기고 내용을 출력하지 않는다.
set -e
cd "$(dirname "$0")/.."
ENV_FILE=${ASC_ENV_FILE:-$HOME/.appstoreconnect/netkeeper.env}
[ -f "$ENV_FILE" ] || { echo "ERROR: $ENV_FILE 없음" >&2; exit 65; }
. "$ENV_FILE"
[ -d build/NetKeeper.xcarchive ] || { echo "ERROR: 먼저 scripts/archive.sh 실행" >&2; exit 1; }

DESTINATION=upload
[ "${1:-}" = "--export" ] && DESTINATION=export

OPTIONS=$(mktemp -t ExportOptions).plist
cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>$DESTINATION</string>
<key>teamID</key><string>$ASC_TEAM_ID</string>
<key>signingStyle</key><string>automatic</string>
<key>uploadSymbols</key><false/>
<key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST

LOG=build/upload.log
rm -rf build/export
xcodebuild -exportArchive \
  -archivePath build/NetKeeper.xcarchive \
  -exportOptionsPlist "$OPTIONS" \
  -exportPath build/export \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" > "$LOG" 2>&1 && STATUS=0 || STATUS=$?
rm -f "$OPTIONS"
grep -E 'error:|warning:|Upload succeeded|EXPORT (SUCCEEDED|FAILED)' "$LOG" | sort -u
echo "log: $LOG"
exit $STATUS
