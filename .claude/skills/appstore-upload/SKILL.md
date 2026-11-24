---
name: appstore-upload
description: >
  NetKeeper(macOS)를 Mac App Store Connect에 빌드 업로드하는 스킬. ASC API로 마지막 빌드 번호 조회 → Info.plist
  CFBundleVersion 증가·커밋·푸시 → swift test → scripts/archive.sh(샌드박스·APPSTORE 플래그·Universal) →
  scripts/appstore-upload.sh(API 키 클라우드 서명, xcodebuild -exportArchive)로 업로드.
  "앱스토어 업로드", "맥 앱스토어 빌드 올려줘", "TestFlight 올려줘", "새 빌드 올려줘", "/appstore-upload" 요청에 사용.
  심사 제출은 `/asc-submit`. .p8 은 경로로만 넘기고 내용을 읽거나 출력하지 않는다.
allowed-tools: [Bash, Read, Edit, Glob, Grep]
---

# appstore-upload

요청: $ARGUMENTS

출시 흐름: **`/appstore-upload`** → `/asc-submit`.

## 전제

- App Store Connect **Team API Key (Admin)** 가 저장소 밖에 있다.
  - 식별자: `~/.appstoreconnect/netkeeper.env` (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`, `ASC_TEAM_ID`, `ASC_BUNDLE_ID`, `ASC_APP_ID`)
  - 키 파일: `ASC_KEY_PATH` 가 가리키는 `.p8` (현소와 같은 팀 키)
- 번들 ID `com.zzaisang.NetKeeper` 는 Developer 계정에 등록돼 있다.
- `ASC_APP_ID` 가 비어 있으면 App Store Connect 웹에서 앱을 아직 만들지 않은 것이다(API 로는 앱을 만들 수 없다). 멈추고
  사용자에게 요청한다: Apps → + → New App → macOS, 이름, 기본 언어, Bundle ID `com.zzaisang.NetKeeper`, SKU. 만든 뒤
  `scripts/asc.sh GET 'apps?filter%5BbundleId%5D=com.zzaisang.NetKeeper'` 로 id 를 찾아 env 의 `ASC_APP_ID=` 에 적는다.
- 서명: 이 Mac 의 Apple Development 인증서로 아카이브를 개발 서명하고, export 때 API 키 + `-allowProvisioningUpdates`
  로 Apple Distribution·Mac Installer 인증서와 Mac App Store 프로파일을 클라우드에서 받아 다시 서명한다.
  로컬 배포 인증서나 Xcode 로그인은 필요 없다.
- App Store판은 `-D APPSTORE` 로 빌드해 샌드박스에서 못 쓰는 기능(Instant Hotspot, macOS 암호 가져오기)을 끈다
  (`Sources/NetKeeper/Distribution.swift`). entitlements 는 `appstore/NetKeeper.entitlements`.
- `Info.plist` 의 `ITSAppUsesNonExemptEncryption=false` 로 수출 규정 질문이 뜨지 않는다.

## 절차

### 0. 사전 확인

```bash
git status --short            # 깨끗해야 한다
git fetch -q origin && git status -sb | head -1   # origin/main 과 동기화
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" -c "Print :CFBundleVersion" Info.plist
```

마지막 업로드 빌드 번호는 API 로 조회한다(사용자에게 묻지 않는다):

```bash
. ~/.appstoreconnect/netkeeper.env
scripts/asc.sh GET "builds?filter%5Bapp%5D=$ASC_APP_ID&sort=-uploadedDate&limit=3&fields%5Bbuilds%5D=version,uploadedDate,processingState" |
  python3 -c 'import json,sys;[print(b["attributes"]) for b in json.load(sys.stdin)["data"]]'
```

새 빌드 번호 `N` = max(조회 결과, Info.plist 값) + 1. 방금 올린 빌드는 수 분간 목록에 안 보일 수 있다.
마케팅 버전(`CFBundleShortVersionString`)은 사용자가 요청할 때만 바꾼다.

### 1. 빌드 번호 증가 → 커밋 → 푸시

```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $N" Info.plist
git add Info.plist
git commit -m "Bump build number to $N"     # 본문은 한국어로 업로드 목적 한 줄
git push origin HEAD:main
```

### 2. 테스트 → 아카이브

```bash
swift test 2>&1 | grep -E "Executed .* tests|error|failed"
scripts/archive.sh            # → build/NetKeeper.xcarchive
```

`archived: … (버전 build N, team …)` 줄의 빌드 번호가 `N` 인지 확인한다.

### 3. 업로드

```bash
scripts/appstore-upload.sh            # 처음이거나 서명이 의심되면 먼저 --export 로 .pkg 만 만들어 확인
```

성공 기준: 출력에 `** EXPORT SUCCEEDED **` (업로드 모드면 `Upload succeeded` 도 함께). 전체 로그는 `build/upload.log`.

### 4. 보고

- 업로드한 버전·빌드, 커밋 SHA
- App Store Connect 처리에 보통 10~30분. 처리가 끝나면 TestFlight 탭과 `/asc-submit` 에서 쓸 수 있다.
- 로그의 `warning:` 줄은 그대로 전달한다.

## 실패 대응

| 증상 | 원인 | 조치 |
|---|---|---|
| `bundle version must be higher` / 중복 빌드 번호 | 번호가 기존 이하 | 번호를 더 올려 1단계부터 |
| `No Accounts` / `Failed to Use Accounts` | `-authenticationKey*` 인자 누락 | env 파일 확인 후 스크립트 그대로 재실행 |
| `401` / JWT 생성 실패 | 키 폐기·경로·ID 오류 | 파일 존재·권한 확인, 폐기됐으면 새 Team Key(Admin) 요청 |
| `No suitable application records were found` | ASC 에 앱이 없음 | 전제의 앱 생성 절차 |
| 프로파일·인증서 오류 | 키 권한 부족 또는 entitlements 문제 | Admin 키인지, `appstore/NetKeeper.entitlements` 키가 Mac App Store 에서 허용되는지 확인 |
| `Apple Development 인증서 없음` | 이 Mac 에 개발 인증서 없음 | Xcode → Settings → Accounts 에서 인증서 생성 요청 |

## 하지 말 것

- 빌드 번호를 올리지 않고 업로드
- .p8 내용 읽기·출력·커밋, JWT 출력, Apple ID 비밀번호 요구
- `--export` 로 만든 `.pkg` 를 다른 경로로 수동 업로드
