# Graphify 에이전트 파이프라인 — ENCBA_LOCKER

graphify(지식 그래프) 기반으로 프로젝트를 분석·개선·확장하는 과정을
단계별 에이전트로 정의한 문서. 각 에이전트는 독립 실행 가능하며,
출력을 다음 에이전트의 입력으로 넘긴다.

---

## Agent 0 — Graph Builder (그래프 생성기)

**역할**: 코드베이스를 지식 그래프로 변환한다.

```powershell
# 코드만 인덱싱 (API 키 불필요, 로컬 AST)
graphify extract . --code-only

# 커뮤니티 클러스터링 + 리포트 생성
graphify cluster-only . --no-label --no-viz
```

**출력**: `graphify-out/graph.json`, `graphify-out/GRAPH_REPORT.md`

**유지보수**: 코드 변경 후 `graphify update .` (증분, 무료).
대규모 삭제 후에는 `graphify update . --force`.

**참고**: Supabase SQL(52개 파일)까지 그래프에 넣으려면
`pip install "graphifyy[sql]"` 후 재추출.

---

## Agent 1 — Structure Analyst (구조 분석가)

**역할**: 그래프에서 아키텍처 허브·커뮤니티·순환 의존을 읽어낸다.

```powershell
graphify god-nodes --top 15                 # 핵심 추상화 (가장 연결 많은 노드)
graphify query "질문" --budget 2000         # BFS 탐색 질의
graphify affected "lockerControllerProvider" # 변경 영향도 역추적
graphify explain "AuthController"           # 노드 + 이웃 설명
graphify path "A" "B"                       # 두 노드 간 최단 경로
graphify diagnose multigraph --json         # 엣지 충돌 위험 진단
```

**최신 분석 결과 (2026-08-23, commit d25e4753)**

- 그래프: 3,246 노드 · 3,928 엣지 · 203 커뮤니티
- God nodes: `lockerControllerProvider`(36), `authControllerProvider`(34),
  `Win32Window`(24) → 상태 관리의 중심이 Riverpod 컨트롤러 2개에 집중
- Import cycle: 없음 ✅
- 아키텍처: `core/`(config·routing·storage·theme) +
  `features/auth` + `features/locker`(application·data·domain·presentation·services)
  → 클린 아키텍처 레이어링 준수
- 지식 공백: 고립 노드 2,467개 (대부분 서드파티 archive 패키지 내부 심볼 — 실제 문제 없음)

---

## Agent 2 — Bug Hunter & Improver (버그 사냥꾼)

**역할**: 정적 분석 + 테스트 + 그래프 단서로 결함을 찾아 고친다.

```powershell
C:\flutter\bin\flutter.bat analyze   # 정적 분석
C:\flutter\bin\flutter.bat test      # 전체 테스트 (84개)
graphify affected "수정 대상 심볼"    # 수정 시 영향 범위 확인
```

**최근 실행 결과**

- `flutter analyze`: **No issues found** ✅
- `flutter test`: **84개 전부 통과** ✅
- 수정 완료: `test/widget_test.dart` 군대 칩 재탭 시 발생하던
  히트테스트 경고 → `warnIfMissed: false` 추가 (1254줄과 동일한
  칩 애니메이션 레이어 문제, 테스트는 계속 통과)

**개선 권고 (버그는 아니지만 품질 개선 포인트)**

| 대상 | 크기 | 권고 |
|---|---|---|
| `videos_screen.dart` | 73 KB | 위젯별 파일 분리 (상세·편집 시트·정렬 메뉴) |
| `supabase_locker_repository.dart` | 71 KB | 테이블별 리포지토리 분리 |
| `event_screens.dart` / `event_editor_screen.dart` | 60/54 KB | 폼 섹션 컴포넌트화 |
| `locker_controller.dart` | 1,541줄 | 공지·운영교대·홈커밍 도메인별 서비스로 위임 |

---

## Agent 3 — Feature Recommender (기능 추천가)

**역할**: 그래프의 빈 영역과 기존 기능 조합에서 신규 기능을 도출한다.

**추천 목록 (우선순위순)**

1. **푸시 알림 카테고리별 딥링크 완성** — `push_notification_service.dart`와
   `app_router.dart`가 이미 있으므로, 알림 탭 시 해당 일정/공지 상세로
   직접 이동하는 라우팅 연결이 가장 비용 대비 효과가 크다.
   (`docs/push-notifications-todo.md` 진행 중인 항목과 연결)
2. **출결 통계 개인 화면** — `attendance_report_service.dart`(관리자용 엑셀
   내보내기)이 있으므로, 부원 개인이 자기 출석률·불참 이력을 보는 화면 추가.
3. **운영교대 요청 알림** — `operationSwapRequests` 실시간 채널은 이미
   구독 중(`_operationSwapChannel`). 교대 요청 수신 시 대상자에게
   알림 발송만 추가하면 됨.
4. **영상 출전 선수 필터링** — `VideoTaggedMember` 태그 데이터가
   축적되고 있으므로 "내가 출연한 복기 영상" 모아보기.
5. **일정 iCal 구독 URL** — `calendar_service_*`(네이티브/웹 분기)가
   있으므로, 구독형 캘린더 피드로 외부 캘린더 앱 연동.

---

## Agent 4 — Verifier (검증자)

**역할**: 모든 변경 후 회귀를 증명한다.

```powershell
C:\flutter\bin\flutter.bat analyze
C:\flutter\bin\flutter.bat test
graphify update .          # 그래프를 최신 커밋에 맞춰 갱신
```

**통과 기준**: analyze 0 이슈 · 테스트 전부 통과 · 그래프 freshness가
`git rev-parse HEAD`와 일치.

---

## 실행 순서 요약

```
Agent 0 (그래프 생성) → Agent 1 (구조 분석) → Agent 2 (버그/개선)
→ Agent 3 (기능 추천) → Agent 4 (검증) → (기능 구현 시 Agent 0부터 재실행)
```
