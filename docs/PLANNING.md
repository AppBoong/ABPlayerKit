# 기획서 (Phase 0) — ABPlayerKit / ABShortsKit

> 확정일: 2026-08-03 · 승인자: AppBoong (powerhotdog21@gmail.com)

## 1. 목적

1. **스터디**: AVPlayer/AVFoundation 재생 파이프라인에 대한 이해도 심화
2. **복습**: ohdasiyoung-ios에서 구현했던 숏폼 플레이어(측정 기반 최적화: 블랙스크린 21.6%→7.8%, TTFF p95 456ms→77ms)를 라이브러리 수준으로 재구성
3. **포트폴리오**: 오픈소스 공개로 어필 (독립 레포 2개, 각자 스타/버전 관리)

## 2. 산출물

| 항목 | 값 |
|---|---|
| 형태 | SPM 라이브러리 × 2 (독립 레포 2개) |
| 플레이어 라이브러리 | **ABPlayerKit** — `github.com/AppBoong/ABPlayerKit` |
| 숏츠 라이브러리 | **ABShortsKit** — `github.com/AppBoong/ABShortsKit` (ABPlayerKit을 SPM 의존) |
| 최소 지원 | iOS 16+ |
| 기술 스택 | UIKit 코어 + SwiftUI 래퍼 (`UIViewControllerRepresentable`) |
| 계정 | AppBoong / powerhotdog21@gmail.com, SSH: `github-AppBoong` 별칭 |

## 3. v1 범위

### ABPlayerKit (플레이어)
- AVPlayerLayer 기반 플레이어 뷰 (UIKit) + SwiftUI 래퍼
- 플레이어 래퍼: preroll, 첫 프레임(TTFF) 감지 (`isReadyForDisplay` ∧ `readyToPlay`)
- **재생 등급 상태 머신 명시화** (current / preloaded / instanceOnly / released — 원본의 암묵적 Set 멤버십 개선)
- HLS/MP4 포맷 불가지론 + HLS 튜닝 노브 (`preferredPeakBitRate`, `preferredForwardBufferDuration`, 승격/강등 대칭 처리)
- 루핑, 음소거/AVAudioSession 정책, 백그라운드/포그라운드 처리 (원본 부재 항목)
- **메트릭 모듈**: TTFF/스톨 측정 훅 (DEBUG 게이팅, 옵트인)
- **로컬 캐싱**: MP4 = AVAssetResourceLoader 기반, HLS = AVAssetDownloadTask 기반 (범위는 설계 단계에서 정밀화)

### ABShortsKit (숏폼 피드)
- 수직 페이징 피드 (UICollectionView + `isPagingEnabled`)
- 이중 슬라이딩 윈도우 프리로드 (인스턴스 링/로드 링, **크기 주입 가능** — 원본 하드코딩 개선)
- `willEndDragging` 시점 선제 윈도우 이동 (~300ms 선점)
- 프리로드 취소 (원본 부재), 셀 재사용 시 pause 보장
- ProMotion 프레임레이트 부스트 (옵션)
- 페이지네이션 델리게이트 (데이터 소스는 사용자 주입)
- SwiftUI 래퍼

### 공통
- 각 레포에 Examples/DemoApp (HLS 공개 스트림 + MP4 데모, TTFF 벤치마크)
- swift-testing 기반 유닛 테스트 (윈도우 전략 순수 함수는 필수)
- README(영/한), API 문서(DocC), MIT 라이선스

### v1 제외
- 커스텀 컨트롤 UI 컴포넌트(시크바 등), DRM, 라이브 스트림 특화 기능, 광고

## 4. 진행 프로세스 (Audit 게이트)

| Phase | 내용 | 산출물 | 게이트 |
|---|---|---|---|
| 0 | 기획 | 본 문서 | ✅ 사용자 승인 |
| 1 | 설계 | 아키텍처/공개 API 설계 문서 (두 라이브러리) | 사용자 승인 |
| 2 | ABPlayerKit Core 구현 | 코어 + 테스트 | 사용자 승인 |
| 3 | ABPlayerKit 캐싱·메트릭 + ABShortsKit 구현 | 전 타겟 + 테스트 | 사용자 승인 |
| 4 | SwiftUI 래퍼 + 데모 앱 | 데모 2종 | 사용자 승인 |
| 5 | 검증·문서화·퍼블리시 | 벤치마크, README/DocC, 태그 릴리즈 | 사용자 승인 |

## 5. 멀티에이전트 배분 (Orca)

| 역할 | 모델 |
|---|---|
| 오케스트레이션·기획·audit 판정 | Fable 5 (본 세션) |
| 아키텍처 설계·심층 리뷰 | Opus 5 |
| 구현 (병렬, worktree 분리) | Sonnet + Codex GPT 5.6 |
| 문서·보일러플레이트·단순 작업 | Haiku |

## 6. 설계 결정 방식 및 기본 스탠스 (Phase 1 출발점)

**결정 프로세스**: 설계 에이전트 초안 → 트레이드오프 쟁점은 사용자 결정 → 설계 문서 audit 승인 → 구현.

| 항목 | 기본 스탠스 |
|---|---|
| 아키텍처 | 레이어드(View/Engine/Policy). 앱 아키텍처(TCA/MVVM) 미사용 — 소비자 중립 |
| DI | 컨테이너 없음. init 주입 + 설정 구조체 |
| 추상화 | 테스트 경계에만 protocol. AVPlayer는 얇게 감싸고 과추상화 금지 (스터디 목적상 AVFoundation 가시성 유지) |
| 모듈구조 | 레포당 SPM 멀티 타겟 (코어/메트릭/캐시, 피드/SwiftUI) — 선택적 채택 |
| 테스트 | swift-testing. 순수 로직 100% 목표, AVPlayer 경계는 protocol fake + 데모 벤치마크 |

## 7. 참조

- 원본 구현: `/Users/nhn/Documents/GitHub/ohdasiyoung-ios` (Shorts feature)
  - 핵심: `ShortsPlayerView.swift`, `ShortsReducer.swift`(VideoPlayerWrapper, applyWindowStrategy), `ManageVideoPlayersUseCase.swift`, `ShortsFeedView.swift`
  - 문서: `docs/숏폼-생명주기-현황감사.md`, `docs/숏폼-프리로딩-최적화-정리.md`
- 원본 대비 개선 목록: 상태 enum 명시화, 승격/강등 대칭, 프리로드 취소, 백그라운드 처리, 윈도우 크기 주입, 오디오 세션 정책, 메트릭 DEBUG 게이팅
