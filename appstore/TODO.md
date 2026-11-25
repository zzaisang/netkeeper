# Mac App Store 출시 할 일

앱: NetKeeper (Apple ID `6838803591`, Bundle ID `com.zzaisang.NetKeeper`, macOS 1.0)

## 결정 사항

- 1.0 은 **무료**, 중국 본토를 뺀 174개 국가·지역에 출시한다.
  - 중국 본토는 신규 앱 제출 시 Security Assessment 보고서와 AIGC 서비스 신고를 요구해 제외했다.
- 유료 앱 계약(Paid Apps Agreement)이 활성화되면 **전 세계 US $0.99** (한국 등은 자동 환산)로 바꾼다.
  - 무료일 때 받은 사용자에게는 나중에 유료로 바꿔도 요금이 부과되지 않는다.
- 영어 스토어 이름은 `NetKeeper` 가 다른 계정에서 사용 중이라 **NetKeeper: Auto Wi-Fi Switch** 로 등록했다.

## 완료

- [x] App Store Connect 앱 생성, `~/.appstoreconnect/netkeeper.env` 에 `ASC_APP_ID` 기록
- [x] Category: Utilities / Content Rights: 제3자 콘텐츠 없음
- [x] Age Rating: 모든 항목 없음
- [x] App Privacy: Data Not Collected (Publish 완료)
- [x] App Information (ko·en): 이름, 부제, Privacy Policy URL
- [x] 버전 1.0 (ko·en): Description, Keywords, Promotional Text, Support URL
- [x] App Review: 심사 메모, 연락처(현소 앱과 동일)
- [x] Pricing: 무료 (기준 국가 미국) / Availability: 174개 국가·지역(중국 본토 제외)
- [x] Copyright: `2026 zzaisang`

## 사용자가 할 일 (웹)

- [ ] Business → **Edit Legal Entity** 로 법적 주체 정보 갱신
- [ ] **Paid Apps Agreement** 서명, 은행 계좌·세금 양식(W-8BEN 등) 입력
- [ ] **EU DSA** 판매자(trader) 여부 신고 — 판매자로 신고하면 EU 스토어에 연락처가 공개된다
- [ ] **한국 법 관련 계정 정보** 확인(Complete Compliance Requirements)

## Claude가 할 일

- [x] Mac 스크린샷 제작: 2880×1800, ko·en, 가상 네트워크 이름만 사용 → `appstore/screenshots/1.0/{ko,en-US}/`
  - App Store판에서 꺼진 기능(Instant Hotspot, macOS 암호 가져오기)이 화면에 나오지 않게 한다
  - 촬영 전 `~/Library/Preferences/com.zzaisang.NetKeeper.plist` 백업, 끝나면 복원 후 확인
- [x] `/appstore-upload` — 빌드 업로드
- [ ] `/asc-submit` — **보류**: 사업자 전환을 먼저 끝낸 뒤 다시 제출한다
  - 빌드 3 연결된 상태로 제출 취소(2026-11-26), 버전 상태 `DEVELOPER_REJECTED`
  - 빌드 2 제출(11-25)은 화면 잠금 중 핫스팟 연결 수정을 넣으려고 취소했다
- [ ] 승인 후 사용자가 **Release this version** 을 눌러 출시 (MANUAL)

## 출시 이후

- [ ] 유료 계약이 활성화되면 Pricing 에서 기준 가격 US $0.99 로 변경
- [ ] 샌드박스판에서 Wi-Fi 전환(`associate`)이 실제로 되는지 TestFlight 로 확인
