---
name: asc-submit
description: >
  NetKeeper(macOS) App Store Connect 반영·심사 제출 스킬. scripts/asc.sh 로 macOS 버전 생성 또는 확인 → What's New(ko·en) →
  Mac 스크린샷 업로드 → 업로드된 빌드 연결 → 요약을 보여 주고 사용자 승인 → 심사 제출.
  "심사 제출", "ASC 올려줘", "앱스토어 제출", "스토어 반영", "/asc-submit" 요청에 사용.
  빌드 업로드는 `/appstore-upload` 가 맡는다.
allowed-tools: [Bash, Read, Write, Edit, Glob, Grep]
---

# asc-submit

요청: $ARGUMENTS

출시 흐름: `/appstore-upload` → **`/asc-submit`**. 앱 코드와 git 은 건드리지 않는다.

## 전제

- 모든 호출은 `scripts/asc.sh` (키: `~/.appstoreconnect/netkeeper.env`, `ASC_APP_ID` 필요). JWT·.p8 내용은 출력하지 않는다.
- 플랫폼 `MAC_OS`. 스토어 언어 `ko`(기본), `en-US`.
- 스크린샷 원본: `appstore/screenshots/<버전>/ko/*.png`, `…/en-US/*.png`. 2880×1800 · 2560×1600 · 1440×900 · 1280×800 중
  하나, 파일 이름순으로 올라간다. 폴더가 없으면 직전 버전 스크린샷을 유지할지 묻는다. 촬영은 이 스킬 범위가 아니다.
- ASC 화면 항목은 영어 원래 이름으로 안내한다.

### 첫 출시에만 필요한 웹 설정 (API 로 못 하거나 한 번만 하는 것)

처음 제출이면 아래가 채워졌는지 사용자에게 확인하고, 빠진 것이 있으면 멈춘다.

- App Information: Category **Utilities**, Privacy Policy URL `https://github.com/zzaisang/netkeeper/blob/main/PRIVACY.md`,
  Support URL `https://github.com/zzaisang/netkeeper/issues`
- Pricing and Availability: 가격·판매 국가
- App Privacy: **Data Not Collected**
- Age Rating 설문
- App Review Information: 연락처, Notes 에 아래 "심사 메모" 붙여넣기
- Version: Description·Keywords·Promotional Text (ko·en)

심사 메모(Notes) 초안:

> NetKeeper is a menu bar utility that keeps the Mac online by joining the user's preferred Wi-Fi networks in priority
> order when the current network loses internet access. Location permission is required only because macOS returns
> Wi-Fi network names (SSIDs) to apps with Location Services access. The app checks connectivity by requesting
> https://captive.apple.com and makes no other network requests. To test: open the menu bar icon → Settings…, add two
> nearby networks, then disable internet on the first one; NetKeeper switches to the second.

## 1. 현재 상태 조회

```bash
A=scripts/asc.sh; . ~/.appstoreconnect/netkeeper.env
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist)
$A GET "apps/$ASC_APP_ID/appStoreVersions?filter%5Bplatform%5D=MAC_OS&limit=3&fields%5BappStoreVersions%5D=versionString,appStoreState,releaseType"
$A GET "builds?filter%5Bapp%5D=$ASC_APP_ID&filter%5Bversion%5D=$BUILD&filter%5BpreReleaseVersion.version%5D=$VER&fields%5Bbuilds%5D=version,processingState,expired,uploadedDate"
$A GET "apps/$ASC_APP_ID/reviewSubmissions?limit=3"
```

- 빌드는 `version` 과 `preReleaseVersion.version` 둘 다로 거른다. 결과가 1개가 아니면 멈추고 보고한다.
- 빌드가 없거나 `PROCESSING` 이면 1분 간격으로 최대 30분 기다린다. `INVALID` 면 멈추고 보고한다.
- 대상 버전이 `PREPARE_FOR_SUBMISSION`·`DEVELOPER_REJECTED`·`REJECTED` 로 있으면 그것을 쓴다(`VID`). 없으면 만든다:
  ```bash
  $A POST appStoreVersions '{"data":{"type":"appStoreVersions","attributes":{"platform":"MAC_OS","versionString":"'$VER'","releaseType":"MANUAL"},"relationships":{"app":{"data":{"type":"apps","id":"'$ASC_APP_ID'"}}}}}'
  ```
  `releaseType` 기본 `MANUAL`. 사용자가 원할 때만 `AFTER_APPROVAL`.

## 2. What's New (ko·en)

1. 직전 출시 버전의 whatsNew 를 조회해 형식을 맞춘다: `$A GET "appStoreVersions/<직전VID>/appStoreVersionLocalizations"`
2. 내용은 직전 버전 이후 커밋(`git log --format='%h %s' <직전 bump 커밋>..origin/main`)에서 사용자가 얻는 것만 뽑는다.
   첫 출시면 whatsNew 는 비워 둔다(첫 버전에는 입력란이 없다).
3. 언어별 localization(`LID`)에 PATCH, 4000자 이하:
   ```bash
   $A GET "appStoreVersions/$VID/appStoreVersionLocalizations"     # locale 별 LID
   python3 -c 'import json,sys;print(json.dumps({"data":{"type":"appStoreVersionLocalizations","id":sys.argv[1],"attributes":{"whatsNew":open(sys.argv[2]).read().strip()}}},ensure_ascii=False))' "$LID" "$TMPDIR/whatsnew-ko.txt" > "$TMPDIR/wn.json"
   $A PATCH "appStoreVersionLocalizations/$LID" @"$TMPDIR/wn.json"
   ```
   `en-US` localization 이 없으면 `POST appStoreVersionLocalizations` 로 만든다(locale `en-US`, description 필수).

## 3. 스크린샷

```bash
$A GET "appStoreVersionLocalizations/$LID/appScreenshotSets"
```

- Mac 세트 `screenshotDisplayType` 은 `APP_DESKTOP`. 없으면 만든다:
  `$A POST appScreenshotSets '{"data":{"type":"appScreenshotSets","attributes":{"screenshotDisplayType":"APP_DESKTOP"},"relationships":{"appStoreVersionLocalization":{"data":{"type":"appStoreVersionLocalizations","id":"'$LID'"}}}}}'`
- 업로드(기존 장 삭제 후 이름순): `$A upload-screenshots <setId> appstore/screenshots/$VER/<locale>`
- 20~60초 뒤 `assetDeliveryState.state` 가 모두 `COMPLETE` 인지 확인. `FAILED` 면 해상도 확인.
- 스크린샷에 실제 네트워크·기기 이름이 보이면 올리지 않는다(가상 이름만).

## 4. 빌드 연결

```bash
$A PATCH "appStoreVersions/$VID/relationships/build" '{"data":{"type":"builds","id":"<buildId>"}}'
$A GET "appStoreVersions/$VID?include=build"
```

## 5. 제출 전 요약 → 사용자 승인 (필수)

아래를 보여 주고 **명시적 승인**을 받는다. 승인 없이 6장으로 가지 않는다.

- 버전 `VER` (빌드 `BUILD`), 출시 방식(MANUAL / AFTER_APPROVAL)
- What's New 전문 (ko·en)
- 스크린샷: 언어별 장 수와 상태(COMPLETE n/n)
- 첫 출시면 위 "웹 설정" 항목별 완료 여부
- 개인정보·연령 등급은 직전 값이 이어진다는 안내

## 6. 심사 제출

```bash
$A GET "apps/$ASC_APP_ID/reviewSubmissions?filter%5Bstate%5D=READY_FOR_REVIEW,UNRESOLVED_ISSUES,WAITING_FOR_REVIEW,IN_REVIEW&limit=5"
```

- 열린 제출 건이 없으면:
  ```bash
  RS=$($A POST reviewSubmissions '{"data":{"type":"reviewSubmissions","attributes":{"platform":"MAC_OS"},"relationships":{"app":{"data":{"type":"apps","id":"'$ASC_APP_ID'"}}}}}' | python3 -c 'import json,sys;print(json.load(sys.stdin)["data"]["id"])')
  $A POST reviewSubmissionItems '{"data":{"type":"reviewSubmissionItems","relationships":{"reviewSubmission":{"data":{"type":"reviewSubmissions","id":"'$RS'"}},"appStoreVersion":{"data":{"type":"appStoreVersions","id":"'$VID'"}}}}}'
  $A PATCH "reviewSubmissions/$RS" '{"data":{"type":"reviewSubmissions","id":"'$RS'","attributes":{"submitted":true}}}'
  ```
- `READY_FOR_REVIEW` 건이 있으면 항목을 확인하고 `submitted:true` 만 PATCH.
- `UNRESOLVED_ISSUES` 건이 있으면 `canceled:true` PATCH → `COMPLETE` 될 때까지 30초 간격 대기 → 새로 제출.
- `WAITING_FOR_REVIEW`·`IN_REVIEW` 면 이미 제출된 것. 보고만 한다.

제출 후 `$A GET "appStoreVersions/$VID"` 의 `appStoreState` 가 `WAITING_FOR_REVIEW` 인지 확인한다.

## 7. 보고

- 상태, 제출 시각(한국 시간), 버전·빌드, 스크린샷 장 수, 출시 방식
- MANUAL 이면 "승인 후 ASC 에서 Release this version 을 눌러야 출시된다"

## 실패 대응

| 증상 | 원인 | 조치 |
|---|---|---|
| `ENTITY_STATE_INVALID` + 항목 `REJECTED` | 이전 제출 건 UNRESOLVED_ISSUES | 6장 취소 → COMPLETE 대기 → 새 제출 |
| `ITEM_PART_OF_ANOTHER_SUBMISSION` | 취소가 아직 CANCELING | 30초 간격 재시도 |
| 제출 시 필수 항목 누락 오류 | 첫 출시 웹 설정 미완료 | "웹 설정" 목록 중 빠진 것을 사용자에게 요청 |
| 스크린샷 `IMAGE_INCORRECT_DIMENSIONS` | 해상도 불일치 | 허용 해상도로 다시 만듦 |
| `401` / JWT 실패 | 키 문제 | `/appstore-upload` 실패 대응과 같음 |

## 하지 말 것

- 5장 승인 없이 제출, Release this version(실제 출시) 실행
- 가격·판매 국가·App Privacy·연령 등급을 사용자 요청 없이 변경
- JWT·.p8 출력, Apple ID 비밀번호 요구
