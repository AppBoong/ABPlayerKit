# 설계 미결 쟁점 — 사용자 결정 요청 (Phase 1)

> Phase 1 기준 8건(Q1~Q8) + v0.2 컨트롤 레이어 7건(Q9~Q15, 문서 하단 확정 표). 아래 8건 외의 설계 결정은 각 설계서의 "내가 직접 결정한 사항과 근거"에 근거와 함께 확정해 두었다.
> 여기 남긴 것은 **되돌리는 비용이 크거나(공개 API·레포 구조), 측정 근거 없이는 정할 수 없는** 항목뿐이다.

---

## Q1. HLS 캐싱의 v1 범위 — `ABPlayerKitCache`

**쟁점.** `AVAssetResourceLoader`는 HTTP(S) HLS 재생목록에 사용할 수 없다(Apple이 키 요청 외 용도를 지원하지 않음). 따라서 "MP4는 리소스로더, HLS는 다운로드태스크"라는 기획의 문장은 **HLS 쪽이 투명 캐싱이 아니라 전체 다운로드**를 뜻하게 된다. 숏폼의 실제 요구(첫 세그먼트만 미리 받아두기)와는 성격이 다르다.

| 선택지 | 내용 | 비용/위험 |
|---|---|---|
| A | v1 = MP4 투명 캐싱 + HLS 명시 프리페치(`AVAssetDownloadTask`, 전체 자산). 투명 HLS 캐싱은 v2 | 범위 명확, 3주 내 완결 가능. 단 "숏폼 HLS 캐싱"을 기대한 사용자에겐 부족해 보일 수 있음 |
| B | 로컬 리버스 프록시(`GCDWebServer` 급 자체 구현)로 HLS 세그먼트 투명 캐싱 | 기술적으로 가장 어필됨. 하지만 재생목록 재작성·상대경로·AES 키·백그라운드 수명 등 실패 모드가 많고, 사실상 별도 프로젝트 규모. 의존성 추가 or 자체 HTTP 서버 구현 필요 |
| C | v1에서 캐시 타겟 자체를 제외하고 메트릭·숏츠에 집중 | 일정 최단. 포트폴리오 상 "3타겟" 서사가 약해짐 |

**추천: A.** 근거 — (1) 원본의 측정 서사가 증명한 가치는 캐싱이 아니라 프리로딩이고, 캐싱은 부가 가치다. (2) B는 실패 시 라이브러리 신뢰도를 통째로 깎는다(재생이 아예 안 되는 형태로 실패). (3) A는 README에 "HLS 투명 캐싱은 리버스 프록시가 필요하며 v1 범위 밖"이라고 **이유와 함께** 적는 것 자체가 도메인 이해도의 증거가 된다.

---

## Q2. 프리로드 기본 튜닝값을 무엇으로 할 것인가

**쟁점.** 원본의 `preferredPeakBitRate = 2Mbps` / `preferredForwardBufferDuration = 5s` 중 **후자는 실측상 soft hint로 동작하지 않음**이 확인됐다(세그먼트 ≥6s 스트림). 그리고 총 전송을 지배한 것은 프리로드가 아니라 **착지 셀의 무제한 전방 버퍼링**(5.7초 시청에 53MB, 실시간 소비의 12.2배)이었다. 즉 라이브러리의 기본값이 원본을 그대로 따르면, 원본이 발견한 진짜 문제를 그대로 물려받는다.

| 선택지 | 내용 |
|---|---|
| A | 원본과 동일: preload = 2Mbps/5s, current = 무제한 | 재현성 최고. 원본 수치를 그대로 인용 가능 |
| B | preload = 2Mbps/5s + `preferredMaximumResolution` 추가, **current도 상한 있음**(예: forwardBuffer 30s, maxResolution = 화면 크기) | 과잉 수신 12배 문제를 라이브러리 기본값으로 교정. 단 원본 A/B 수치를 그대로 인용할 수 없게 됨(새 벤치마크 필요) |
| C | 기본은 전부 무제한, 프리셋(`.conservativePreload`, `.dataSaver`)만 제공하고 선택은 소비자 | 라이브러리로서 가장 중립적. 대신 "그냥 쓰면 데이터 폭식"이라는 기본 경험 |

**추천: B(단 current 상한은 `preferredMaximumResolution`만, forwardBuffer는 무제한 유지).** 근거 — 원본 측정이 규명한 1순위 개선점이 착지 셀 정책이고, 이를 기본값에 반영하는 것이 이 라이브러리의 차별점이다. `preferredMaximumResolution`을 화면 픽셀 크기로 거는 것은 화질 체감 손실이 사실상 없으면서(디바이스 해상도 이상은 어차피 못 그림) 렌디션 낭비를 줄이는, 근거가 명확한 유일한 노브다. forwardBuffer까지 건드리면 stall 위험이 생기는데 이건 측정 없이 정할 수 없다. **다만 Phase 5 벤치마크에서 A vs B를 실제로 재서 README에 싣는 것을 전제로 한다.**

---

## Q3. 이벤트 전달 API의 형태

**쟁점.** 공개 API에서 되돌리기 가장 비싼 결정. Swift 6 / SwiftUI 시대에 어떤 형태가 "요즘 라이브러리"로 보이는가와, 메트릭 타겟이 소비자 슬롯을 뺏지 않아야 한다는 제약이 충돌한다.

| 선택지 | 내용 |
|---|---|
| A | 다중 옵저버 + `ABObservationToken` (설계서 초안) | 다중 구독 자연스러움, 해제 보장(원본 약점 #12 봉쇄), UIKit 친화. 다소 구식으로 보일 수 있음 |
| B | `AsyncStream<ABPlayerEvent>` 프로퍼티 | 모던함. 단 다중 구독 시 스트림 팬아웃을 직접 구현해야 하고, 이벤트 순서/드롭 정책과 `for await` Task 수명 관리를 소비자에게 떠넘김. **첫 프레임 이벤트가 한 틱 늦게 도착**해 TTFF 계측 정확도를 해칠 수 있음 |
| C | A + `@Observable`(iOS 17+) 상태 프로퍼티 병행 | SwiftUI 소비자 경험 최고. iOS 16 지원과 충돌(조건부 컴파일 필요) |

**추천: A.** 근거 — TTFF 정확도가 이 라이브러리의 핵심 주장인데 B는 그 정확도를 구조적으로 흐린다(스트림 버퍼링·스케줄링). A로 시작하면 나중에 `events` AsyncStream을 **추가**하는 것이 소스 호환 변경이라 손해가 없다. 반대로 B로 시작하면 되돌릴 수 없다.

---

## Q4. `AVAudioSession` 소유권

**쟁점.** 숏폼은 무음 스위치 상태에서도 소리가 나야 하는 경우가 많아 `.playback` 카테고리 설정이 필요한데, `AVAudioSession`은 **앱 전역 자원**이다. 라이브러리가 이를 건드리면 통화/음악 앱 연동 등에서 소비자 앱의 동작을 조용히 망가뜨린다.

| 선택지 | 내용 |
|---|---|
| A | 기본 `.unmanaged`(호출 0건) + `ABAudioSession.activate(_:)` 명시 API 제공 | 안전. 소비자가 한 줄 더 써야 하고, 안 쓰면 "소리가 안 난다"는 이슈가 반복 유입될 수 있음 |
| B | 피드가 `setActive(true)` 시점에 `.playback` 자동 적용, 이탈 시 복원 | 즉시 동작하는 좋은 기본 경험. 소비자 앱의 세션을 침범 |
| C | 기본은 `.unmanaged`이되, 설정으로 자동 적용을 켤 수 있고 **README 첫 화면에 명시** | 절충 |

**추천: C.** 근거 — A의 안전성을 유지하면서 "소리가 안 나요" 이슈를 문서로 흡수한다. 자동 적용을 켰을 때는 이전 카테고리를 저장했다가 `setActive(false)`에서 복원하는 것까지 구현한다(복원 실패는 이벤트로만 알림, throw 없음).

---

## Q5. 백그라운드 기본 정책

**쟁점.** 원본은 처리가 전무했다(약점 #5). 무엇을 기본값으로 할지는 "복귀 시 즉시 재생"과 "백그라운드 자원 점유" 사이의 트레이드오프다.

| 선택지 | 내용 |
|---|---|
| A | `.pause` — 일시정지만. 복귀 시 직전 상태 복원 | 복귀가 가장 빠름. 백그라운드에서 버퍼/디코더는 유지(메모리 압력 시 jetsam 위험) |
| B | `.pauseAndDetachLayer` — pause + `AVPlayerLayer.player = nil` | 디코더 해제로 메모리 압력 완화. 복귀 시 레이어 재부착으로 수십~수백 ms 검은 화면 가능 |
| C | `.demoteToInstance` — 아이템까지 해제 | 백그라운드 네트워크 0. 복귀 시 전 셀 재로드(TTFF 리그레션) |

**추천: A를 기본, B를 문서에서 권장 옵션으로.** 근거 — 라이브러리 기본값은 "놀라지 않는 동작"이어야 한다. 백그라운드 진입 후 복귀했더니 검은 화면이 뜨는 것은 놀라움이다. B/C는 장시간 백그라운드나 메모리 압력 대응용으로 소비자가 선택한다. (추가 옵션: 백그라운드 진입 후 N초 경과 시 자동으로 B/C로 격상하는 타이머 — v1 제외 추천)

---

## Q6. 오버레이 주입 방식 — UIKit 전용 vs SwiftUI 호스팅 지원

**쟁점.** 원본은 SwiftUI 호스팅 셀에서 **스크롤 중 오버레이가 셀 프레임과 따로 움직이는** 문제를 겪고 전 오버레이를 UIKit으로 되돌렸다(ShortsFeedView 주석 :100-104). 그런데 2026년 소비자 대부분은 SwiftUI로 오버레이를 짜고 싶어 한다.

| 선택지 | 내용 |
|---|---|
| A | UIKit `UIView` 오버레이만 지원. SwiftUI 소비자는 스스로 `UIHostingController`를 감싸 넘김 | 라이브러리는 안전. "SwiftUI 지원 안 함"으로 보여 채택률 손해 |
| B | `UIView` + SwiftUI `@ViewBuilder` 양쪽 지원. SwiftUI 경로는 셀당 `UIHostingController` 자식 + safe area 무시 강제 | 채택률 최고. 원본이 겪은 어긋남이 재발할 위험을 라이브러리가 떠안음 |
| C | B + **데모 앱에 스크롤 지터 회귀 측정**(히치율)을 넣어 SwiftUI 경로의 비용을 수치로 공개 | B의 위험을 측정으로 관리. 작업량 증가 |

**추천: C.** 근거 — 원본 문서가 "숏폼 스크롤 히치율은 미측정 — 6개 핵심 지표 중 유일한 공백"이라고 스스로 적어 뒀다. 이 공백을 이 프로젝트에서 메우면 서사가 닫힌다. SwiftUI 오버레이의 히치 비용을 수치로 제시하는 것은 그 자체로 강한 포트폴리오 소재다. 단 Phase 4~5 작업량이 늘어난다.

---

## Q7. Swift 언어 모드와 최소 지원 버전

**쟁점.** 기획은 iOS 16 + Swift 5.9다. 2026년 시점에 새 오픈소스 라이브러리를 Swift 5 언어 모드로 내는 것은 "구식"으로 보일 수 있고, 반대로 Swift 6 언어 모드는 `AVFoundation`의 미완성 `Sendable` 어노테이션과 싸워야 한다.

| 선택지 | 내용 |
|---|---|
| A | iOS 16 + Swift 5.9 언어 모드 + `StrictConcurrency` 실험 플래그(경고 0 유지) | 호환성 최대. 소비자가 Swift 6 모드여도 라이브러리는 그대로 링크됨. "strict-concurrency ready"라고 표기 |
| B | iOS 17 + Swift 6 언어 모드 | 가장 모던. iOS 16 사용자 배제, `@preconcurrency import AVFoundation` 회피 작업 다수 |
| C | Package.swift에 `swiftLanguageModes: [.v6, .v5]` 병기 (Swift 6.0 툴체인 필요) | 양쪽 만족. 툴체인 하한이 올라가고 CI 매트릭스가 2배 |

**추천: A.** 근거 — 기획서 확정 사항이고, 목적(스터디·복습·포트폴리오) 어디에도 iOS 16 배제로 얻는 것이 없다. 대신 **모든 타겟에서 strict concurrency 경고 0**을 CI 게이트로 걸고 README에 명시하면, "Swift 6 준비됨"의 실질을 언어 모드 표기 없이 증명할 수 있다.

---

## Q8. 강등 시 재생 위치와 "되돌아가기 이어보기"

**쟁점.** 현재 셀 → 프리로드 셀로 강등될 때 재생 위치를 유지할지 0으로 되감을지, 그리고 윈도우를 벗어났다 돌아온 항목의 위치를 복원할지. 원본은 "윈도우 밖에 나갔다 돌아오면 0초부터"이며 이를 숏폼 표준으로 문서화했다.

| 선택지 | 내용 |
|---|---|
| A | 강등 시 위치 유지, 윈도우 이탈 후 복귀는 0초부터 (원본과 동일) | 단순. 되돌아가면 처음부터 — 숏폼 관례에 부합 |
| B | 강등 시 `seek(.zero)` | 되돌아갔을 때 항상 처음부터라 일관됨. 단 1칸 실수 스와이프 후 복귀 시 재생 위치가 날아감 |
| C | 인덱스별 재생 위치를 라이브러리가 기억해 복귀 시 복원 (`ABResumePolicy`) | 사용자 경험은 가장 좋음. 상태를 하나 더 소유하게 되고(YAGNI 위반 소지), 아이템 재생성 후 seek이 TTFF를 늘림 |

**추천: A (설정 `rewindOnDemotion`은 두되 기본 false).** 근거 — C는 "첫 프레임 즉시 표시"라는 라이브러리의 핵심 주장과 정면으로 상충한다(복원 seek이 TTFF를 늘린다). 되돌아가기 이어보기가 필요한 소비자는 `feed(_:didChangeCurrentIndexTo:)`에서 직접 위치를 저장하고 `player(at:)`으로 seek할 수 있으므로, 라이브러리가 소유할 이유가 없다.

---

## ✅ 확정 결정 (사용자 승인, 2026-08-03)

| # | 쟁점 | 확정 | 비고 |
|---|---|---|---|
| Q1 | HLS 캐싱 v1 범위 | **A** — MP4 투명 캐싱 + HLS 명시 프리페치(AVAssetDownloadTask), 투명 HLS(리버스 프록시)는 v2 | 추천안 채택 |
| Q2 | 프리로드/재생 기본 튜닝값 | **B** — current 기본에 `preferredMaximumResolution` = 화면 크기 상한 추가. Phase 5에서 A/B 벤치마크 | 추천안 채택 |
| Q3 | 이벤트 API 형태 | **A** — 다중 옵저버 + `ABObservationToken` | 추천안 채택 |
| Q4 | AVAudioSession 소유권 | **C** — 기본 `.unmanaged` + 설정으로 자동 적용 옵트인(이전 카테고리 복원 포함), README 명시 | 추천안 채택 |
| Q5 | 백그라운드 기본 정책 | **A** — `.pause` 기본, `.pauseAndDetachLayer` 권장 옵션 문서화 | 추천안 채택 |
| Q6 | 오버레이 주입 방식 | **A** — **UIKit `UIView` 오버레이만 지원.** SwiftUI 소비자는 직접 `UIHostingController` 래핑. 원본이 겪은 호스팅 어긋남 위험을 라이브러리가 떠안지 않음 | 추천(C)과 다른 사용자 결정 |
| Q7 | 언어 모드/최소 버전 | **B** — **iOS 17+ · Swift 6 언어 모드.** `@Observable` 사용 가능해짐(단 Q3 결정에 따라 이벤트는 옵저버+토큰 유지). PLANNING.md 갱신됨 | 추천(A)과 다른 사용자 결정 — Phase 0의 iOS 16+를 변경 |
| Q8 | 강등 시 위치·이어보기 | **C** — **라이브러리가 인덱스별 재생 위치를 기억·복원 (`ABResumePolicy`).** 복원 seek이 TTFF에 미치는 영향은 메트릭에서 `resumed` 여부로 구분 집계해 관리 | 추천(A)과 다른 사용자 결정 |

### 결정이 설계에 미치는 영향
- **Q7**: Package.swift `platforms: [.iOS(.v17)]`, `swiftLanguageModes: [.v6]`. AVFoundation 경계에 `@preconcurrency` 필요 지점 예상. TTFF 시계로 `ContinuousClock` 검토 가능.
- **Q6**: `ABShortsFeed`(SwiftUI 래퍼)의 `@ViewBuilder overlay` 파라미터 제거 → 오버레이는 `UIView` 반환 클로저로 통일.
- **Q8**: `ABShortsKit`에 `ABResumePolicy { .none, .rememberWindow(capacity: Int) }` 추가. 위치 저장 시점 = 강등/해제 직전, 복원 시점 = current 승격 시 첫 프레임 표시 전 seek. `.none`이 기본값이 아니라 **`.rememberWindow`가 기본** (사용자 의도 반영). 메트릭 `ABMetricSample`에 `resumedFromTime: CFTimeInterval?` 필드 추가.

---

## ✅ 확정 결정 — v0.2 컨트롤 레이어 (사용자 승인, 2026-08-04)

> 쟁점 서술과 선택지는 `docs/DESIGN-v0.2-CONTROLS.md` §12에 있다.

| # | 쟁점 | 확정 | 비고 |
|---|---|---|---|
| Q9 | 컨트롤 레이어의 타겟 위치 | **A** — 신규 타겟 `ABPlayerKitControls`(UIKit 코어 + SwiftUI 래퍼). **단 수정안 1건**: 공유 순수 타입 `ABSeekBarGeometry`·`ABTimeFormatter`는 컨트롤이 아니라 **코어 `ABPlayerKit`의 public API**로 승격 | 추천안 + 사용자 수정안. 근거 = ABShortsKit v0.2가 숏폼 제스처 UI(하단 슬림 시크바, 탭 재생/일시정지, 롱프레스 2× 배속)에서 재사용. **숏폼 UI 자체는 이번 사이클 범위 밖** |
| Q10 | `ABPlayerEvent`에 케이스 4개 추가 (소스 호환 파괴) | **A** — 그대로 추가. `ABPlayerEvent`를 비전수(non-exhaustive)로 취급하고 `default`를 두라는 규약을 README·DocC·CHANGELOG **3곳 전부**에 명시 | 추천안 채택 |
| Q11 | 주기 시간 관찰을 누가 켜는가 | **A** — `configuration.periodicTimeInterval`이 유일한 스위치. 컨트롤 뷰가 부착 시 자기 값으로 설정하고 해제 시 **부착 이전 값으로 복원** | 추천안 채택. 복원은 테스트로 게이팅 |
| Q12 | 배속 ≠ 1일 때 preroll rate | **A** — `configuration.prerollRate`를 문자 그대로 사용. `playbackRate`와 연동하지 않음 | 추천안 채택. Phase 5 벤치마크에서 2× 승격 지연이 실측되면 v0.3 재검토 |
| Q13 | `ABPlayerControlsStyle`의 `Sendable` | **A** — 채택을 시도하고 Swift 6에서 경고가 나면 떼고 `Equatable`만 유지. **`@unchecked Sendable` 금지** | 추천안 채택. 다이나믹 컬러 유지를 위해 `UIColor` 사용 |
| Q14 | 컨트롤 구현 스택 | **A** — UIKit 코어 + SwiftUI 래퍼 | 추천안 채택. PLANNING §2 기술 스택 일치 + 드래그 제스처 정밀도 |
| Q15 | 기본 `periodicTimeInterval` | **A** — 0.25초 | 추천안 채택. Phase 5에서 Instruments 실측치를 README에 기재 |

### 결정이 설계에 미치는 영향
- **Q9 수정안**: 코어에 `Sources/ABPlayerKit/Presentation/` 신설 → `ABSeekBarGeometry`(public struct), `ABTimeFormatter`(public enum). 두 타입은 `UIKit` 비의존(`CoreGraphics` + `CoreMedia`만)이므로 코어 설계서 §1의 비목표("커스텀 컨트롤 **UI**")를 침범하지 않는다. 테스트는 `ABPlayerKitTests`로 이관, 태스크 B5 → A4로 이동(C2·C3이 A4에 의존). v0.2부터 semver 대상이므로 확장은 **메서드 추가로만** 한다.
- **Q10**: `CHANGELOG.md`에 "전수 `switch` 사용 시 재컴파일 에러" 주의 문구 필수. `ABPlayerEvent` DocC 심볼 주석에도 동일 규약 기재.
- **Q11**: `ABPlayerControlsView`가 `previousPeriodicTimeInterval`을 보관하고 `player` didSet / `deinit`에서 복원.
- **Q13**: 경고 발생 시 `Sendable`을 떼는 것이 기본 동작 — 컴파일을 통과시키기 위해 `@unchecked`를 붙이는 것은 `MainActor.assumeIsolated` 금지와 같은 이유로 금지된다.
- **Q15**: `ABPlayerControlsConfiguration.periodicTimeInterval` 기본값 0.25초. 소비자 조절 가능.
