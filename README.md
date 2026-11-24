# NetKeeper

인터넷이 끊기지 않도록 선호 네트워크 우선순위대로 자동 전환하는 macOS 메뉴바 앱.
Wi-Fi와 iPhone 핫스팟(셀룰러)을 하나의 우선순위 목록으로 관리한다.

## 빌드·설치

```sh
./build.sh
cp -R build/NetKeeper.app /Applications/
open /Applications/NetKeeper.app
```

- Apple Development 인증서가 있으면 그것으로 서명한다. 재빌드해도 위치 권한·키체인 접근이 유지된다.
- 테스트: `swift test`

## 처음 실행 시 필요한 권한

| 권한 | 용도 |
|---|---|
| 위치 서비스 | 주변 Wi-Fi 이름(SSID) 조회 (macOS 14+ 요구사항) |
| 손쉬운 사용 | Instant Hotspot — Wi-Fi 메뉴의 iPhone 항목을 대신 눌러 핫스팟을 깨움 |
| 관리자 인증 (네트워크당 1회) | macOS에 저장된 Wi-Fi 암호 가져오기 |

## 동작

- 5초마다 `captive.apple.com`으로 실제 인터넷을 확인한다. Wi-Fi 연결 변화는 macOS 이벤트로 즉시 감지한다.
- 연속 2회 불통이면 그 네트워크를 5분간 제외하고 다음 순위로 전환한다.
- 1순위가 아닌 네트워크를 쓰는 중이면 30초마다 스캔해 상위 네트워크로 돌아간다.
- 팝오버에서 직접 고른 네트워크는 인터넷이 되는 동안 유지한다.
- 메뉴바 아이콘 뱃지: 없음 = Wi-Fi 정상, 파랑 = 셀룰러, 빨강 = 끊김, 회색 고리 = 자동 전환 꺼짐.
- 최근 60분 연결 기록을 1분 단위 막대로 보여준다 (메모리 보관, 앱 재시작 시 초기화).
- 주기·불통 판정 횟수·제외 시간은 설정 > 일반에서 조정한다.

## 언어

한국어(개발 언어)와 영어를 지원한다. 기본은 시스템 언어를 따르며 설정 > 일반 > 언어에서 바꿀 수 있다.
영어 문구는 `Resources/en.lproj/Localizable.strings`에 있고, 키는 한국어 원문이다.

## 제약

- Instant Hotspot은 공개 API가 없어 Control Center 접근성 식별자(`wifi-network-<SSID>`)에 의존한다. macOS 업데이트로 바뀌면 `InstantHotspot.swift`를 고친다.
- 보안 Wi-Fi는 앱에 암호가 있어야 연결된다. macOS에 저장된 네트워크는 암호를 가져와 쓴다.
