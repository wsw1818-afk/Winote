# Winote 개발 티켓

> MVP 개발을 위한 작업 티켓 목록
> 우선순위: P0 (필수) > P1 (중요) > P2 (선택)

---

## Phase 0: PoC - 필기감 검증 (2-4일)

> **목표:** 상업용 필기감 달성 가능 여부 검증
> **통과 기준:** 입력 지연 <10ms, 손바닥 거부 100%, 필기감 만족

### TICKET-000: PoC 프로젝트 생성
**우선순위:** P0
**예상 시간:** 1시간
**담당:** -

**설명:**
최소한의 Flutter 프로젝트로 필기 테스트 환경 구축

**작업 내용:**
- [ ] Flutter 프로젝트 생성 (최소 설정)
- [ ] 전체 화면 캔버스 위젯 생성
- [ ] 터치/펜 입력 기본 수신
- [ ] Android 타블렛 빌드 및 설치

**명령어:**
```bash
flutter create --org com.winote --project-name winote_poc --platforms android,windows .
```

**완료 조건:**
- Galaxy Tab에서 앱 실행 가능
- 화면 터치 시 좌표 출력

---

### TICKET-001A: 펜/터치 분리 검증
**우선순위:** P0
**예상 시간:** 2시간
**담당:** -

**설명:**
PointerDeviceKind를 사용한 펜/터치 입력 분리 검증

**작업 내용:**
- [ ] Listener 위젯으로 PointerEvent 수신
- [ ] PointerDeviceKind.stylus 감지 로직
- [ ] 펜 입력 시 손가락 터치 무시 (손바닥 거부)
- [ ] 디버그 오버레이: 현재 입력 타입 표시
- [ ] S Pen 버튼 상태 확인 (가능한 경우)

**파일:**
- `lib/poc/palm_rejection_test.dart`

**테스트 시나리오:**
1. 펜으로 그리면서 손바닥 대기 → 손바닥 무시되어야 함
2. 손가락 두 개로 줌/팬 → 줌/팬 동작해야 함
3. 펜 떼고 손가락으로 터치 → 터치 감지되어야 함

**성공 기준:**
- 펜 입력 중 터치 100% 무시
- 펜/터치 전환 시 오류 없음

---

### TICKET-001B: 입력 지연 측정
**우선순위:** P0
**예상 시간:** 2시간
**담당:** -

**설명:**
스타일러스 입력부터 화면 렌더링까지 지연 시간 측정

**작업 내용:**
- [ ] 고해상도 타이머로 입력 시작 시간 기록
- [ ] CustomPainter.paint() 호출 시간 기록
- [ ] 지연 시간 계산 및 평균/최대값 표시
- [ ] 120Hz 디스플레이 고려 (8.3ms 프레임)
- [ ] 디버그 오버레이: 실시간 지연 표시

**측정 방법:**
```dart
// 입력 시작
onPointerDown: (event) {
  _inputStartTime = DateTime.now().microsecondsSinceEpoch;
}

// 렌더링 완료
void paint(Canvas canvas, Size size) {
  final renderTime = DateTime.now().microsecondsSinceEpoch;
  final latency = renderTime - _inputStartTime; // μs
  _recordLatency(latency);
}
```

**성공 기준:**
- 평균 입력 지연 < 10ms
- 최대 입력 지연 < 16ms (60fps 기준)

---

### TICKET-001C: 기본 스트로크 렌더링
**우선순위:** P0
**예상 시간:** 3시간
**담당:** -

**설명:**
압력/기울기 반영 기본 스트로크 렌더링

**작업 내용:**
- [ ] StrokePoint 데이터 클래스 (x, y, pressure, tilt, timestamp)
- [ ] CustomPainter로 스트로크 렌더링
- [ ] 압력에 따른 굵기 변화 (0.5x ~ 2.0x)
- [ ] 기본 스무딩 적용 (3점 평균)
- [ ] 펜 들어올릴 때 끝점 처리

**테스트 시나리오:**
1. 가볍게 터치 → 얇은 선
2. 세게 누르며 그리기 → 굵은 선
3. 빠르게 그리기 → 끊김 없이 연결
4. 천천히 정밀하게 그리기 → 부드러운 곡선

**성공 기준:**
- 압력 변화가 자연스럽게 반영됨
- 끊김/튀는 현상 없음

---

### TICKET-001D: PoC 평가 및 Go/No-Go
**우선순위:** P0
**예상 시간:** 2시간
**담당:** -

**설명:**
PoC 결과 종합 평가 및 MVP 진행 결정

**평가 항목:**

| 항목 | 목표 | 측정값 | 통과 |
|------|------|--------|------|
| 입력 지연 (평균) | < 10ms | ___ ms | ☐ |
| 입력 지연 (최대) | < 16ms | ___ ms | ☐ |
| 손바닥 거부율 | 100% | ___% | ☐ |
| 압력 민감도 | 자연스러움 | ☐좋음 ☐보통 ☐나쁨 | ☐ |
| 스무딩 품질 | 자연스러움 | ☐좋음 ☐보통 ☐나쁨 | ☐ |
| 프레임 드롭 | 없음 | ☐없음 ☐가끔 ☐자주 | ☐ |

**결정 기준:**
- **GO:** 모든 항목 통과 → MVP 진행
- **PIVOT:** 1-2개 항목 미통과 → 해당 영역 추가 연구 후 재평가
- **NO-GO:** 3개 이상 미통과 → 기술 스택 재검토 (Native 고려)

**산출물:**
- [ ] PoC 결과 보고서
- [ ] 측정 데이터 스크린샷
- [ ] Go/No-Go 결정 문서

---

## Phase 1: 프로젝트 기반 (Week 1)

### TICKET-002: 프로젝트 초기화
**우선순위:** P0
**예상 시간:** 2시간
**담당:** -

**설명:**
Flutter 프로젝트 생성 및 기본 구조 설정

**작업 내용:**
- [ ] Flutter 프로젝트 생성 (`flutter create`)
- [ ] 폴더 구조 생성 (core, data, domain, presentation)
- [ ] 기본 패키지 설치 (riverpod, go_router, drift, path_provider)
- [ ] 린트 설정 (analysis_options.yaml)
- [ ] Git 초기화 및 .gitignore 설정

**명령어:**
```bash
flutter create --org com.winote --project-name winote --platforms android,windows .
```

**완료 조건:**
- 앱이 Android/Windows에서 빌드되고 실행됨
- 폴더 구조가 ARCHITECTURE.md와 일치

---

### TICKET-003: 데이터 모델 정의
**우선순위:** P0
**예상 시간:** 3시간
**담당:** -

**설명:**
핵심 엔티티 클래스 및 데이터 모델 구현 (바이너리 저장 고려)

**작업 내용:**
- [ ] Folder 엔티티 생성
- [ ] Note 엔티티 생성
- [ ] Page 엔티티 생성
- [ ] Stroke 엔티티 생성 (BoundingBox 포함)
- [ ] StrokePoint 엔티티 생성 (바이너리 직렬화 메서드)
- [ ] BoundingBox 엔티티 생성
- [ ] Attachment 엔티티 생성
- [ ] 단위 테스트 작성

**파일:**
- `lib/domain/entities/folder.dart`
- `lib/domain/entities/note.dart`
- `lib/domain/entities/page.dart`
- `lib/domain/entities/stroke.dart`
- `lib/domain/entities/stroke_point.dart`
- `lib/domain/entities/bounding_box.dart`
- `lib/domain/entities/attachment.dart`

**완료 조건:**
- 모든 엔티티 클래스가 정의됨
- 바이너리 직렬화 메서드 테스트 통과

---

### TICKET-004: 로컬 데이터베이스 설정 (Drift)
**우선순위:** P0
**예상 시간:** 4시간
**담당:** -

**설명:**
SQLite 데이터베이스 스키마 및 DAO 구현

**작업 내용:**
- [ ] Drift 테이블 정의 (Folders, Notes, Pages, Attachments)
- [ ] AppDatabase 클래스 구현
- [ ] DAO 클래스 구현 (FolderDao, NoteDao, PageDao)
- [ ] 마이그레이션 전략 설정
- [ ] 통합 테스트 작성

**파일:**
- `lib/data/datasources/local/database/app_database.dart`
- `lib/data/datasources/local/database/tables/*.dart`
- `lib/data/datasources/local/database/daos/*.dart`

**완료 조건:**
- 데이터베이스 생성됨
- CRUD 작업이 정상 동작 (테스트 통과)

---

### TICKET-005: 바이너리 스트로크 저장소 구현
**우선순위:** P0
**예상 시간:** 4시간
**담당:** -

**설명:**
스트로크 데이터를 바이너리 포맷으로 저장 (JSON 대신)

**작업 내용:**
- [ ] 앱 문서 디렉토리 구조 생성
- [ ] BinaryStrokeStorage 클래스 구현
- [ ] .strokes.bin 파일 포맷 구현 (헤더 + 인덱스 + 데이터)
- [ ] 공간 인덱스 직렬화 (QuadTree 저장)
- [ ] 썸네일 이미지 저장 구현
- [ ] PDF/이미지 첨부파일 저장 구현
- [ ] 파일 삭제 및 정리 로직
- [ ] 성능 테스트 (500 스트로크 로드 < 100ms)

**파일:**
- `lib/data/datasources/local/binary_stroke_storage.dart`
- `lib/data/datasources/local/file_storage.dart`
- `lib/core/utils/file_utils.dart`

**완료 조건:**
- 스트로크 데이터가 바이너리 파일로 저장/로드됨
- 500 스트로크 로드 시간 < 100ms
- 첨부파일이 올바른 위치에 저장됨

---

### TICKET-006: 레포지토리 구현
**우선순위:** P0
**예상 시간:** 4시간
**담당:** -

**설명:**
데이터 접근 레포지토리 패턴 구현

**작업 내용:**
- [ ] NoteRepository 인터페이스 정의
- [ ] NoteRepositoryImpl 구현 (DB + 파일)
- [ ] FolderRepository 인터페이스/구현
- [ ] StrokeRepository 인터페이스/구현
- [ ] 단위 테스트 작성 (목 객체 사용)

**파일:**
- `lib/domain/repositories/*.dart`
- `lib/data/repositories/*_impl.dart`

**완료 조건:**
- 레포지토리를 통해 노트 CRUD 가능
- 테스트 커버리지 80% 이상

---

## Phase 2: 필기 엔진 (Week 2-3)

### TICKET-007A: 스트로크 엔진 - 입력 파이프라인
**우선순위:** P0
**예상 시간:** 4시간
**담당:** -

**설명:**
필기 입력 처리 파이프라인 (Input → Filter → Resample)

**작업 내용:**
- [ ] StrokeEngine 클래스 기본 구조
- [ ] 스트로크 시작/계속/종료 로직
- [ ] 1-Euro Filter 구현 (노이즈 제거)
- [ ] 재샘플링 로직 (균일 간격 2-3px)
- [ ] 입력 지연 측정 로직
- [ ] 단위 테스트 작성

**파일:**
- `lib/domain/services/stroke_engine.dart`
- `lib/domain/services/input_filter.dart`
- `test/unit/stroke_engine_test.dart`

**완료 조건:**
- 필터링 후 노이즈 감소 확인
- 재샘플링 후 균일 간격 포인트
- 입력 지연 < 5ms (필터링만)

---

### TICKET-007B: 스트로크 엔진 - 스무딩 & 메쉬 생성
**우선순위:** P0
**예상 시간:** 4시간
**담당:** -

**설명:**
스트로크 스무딩 및 가변 굵기 메쉬 생성

**작업 내용:**
- [ ] Catmull-Rom 스플라인 보간 구현
- [ ] 베지어 곡선 변환 (선택적)
- [ ] 압력 → 굵기 매핑 로직
- [ ] 기울기 → 각도 반영 (선택적)
- [ ] Triangle Strip 메쉬 생성
- [ ] 단위 테스트 작성

**파일:**
- `lib/domain/services/stroke_engine.dart`
- `lib/domain/services/mesh_generator.dart`
- `test/unit/smoothing_test.dart`

**완료 조건:**
- 스무딩 후 자연스러운 곡선
- 압력 변화가 굵기에 반영됨
- 메쉬 생성 시간 < 1ms (100포인트 기준)

---

### TICKET-007C: 스트로크 엔진 - 공간 인덱스 & Undo
**우선순위:** P0
**예상 시간:** 3시간
**담당:** -

**설명:**
공간 인덱스(QuadTree) 및 실행취소/재실행 구현

**작업 내용:**
- [ ] QuadTree 클래스 구현
- [ ] 스트로크 삽입/삭제/쿼리
- [ ] 뷰포트 쿼리 최적화
- [ ] 실행취소/재실행 스택 (100단계)
- [ ] 스트로크 선택 (라쏘) 최적화
- [ ] 단위 테스트 작성

**파일:**
- `lib/domain/services/spatial_index.dart`
- `lib/domain/services/stroke_engine.dart`
- `test/unit/quadtree_test.dart`

**완료 조건:**
- 뷰포트 쿼리 O(log n) 성능
- 실행취소/재실행 100단계 동작
- 1000 스트로크 쿼리 < 1ms

---

### TICKET-008A: 캔버스 위젯 - 기본 렌더링
**우선순위:** P0
**예상 시간:** 4시간
**담당:** -

**설명:**
CustomPainter 기반 기본 캔버스 렌더링

**작업 내용:**
- [ ] CanvasWidget 기본 구조 생성
- [ ] 3-Layer 아키텍처 (배경/완료/활성)
- [ ] RepaintBoundary로 레이어 분리
- [ ] 배경 템플릿 렌더링 (빈/줄/모눈/도트)
- [ ] 현재 그리기 중인 스트로크 실시간 렌더링

**파일:**
- `lib/presentation/pages/editor/widgets/canvas_widget.dart`
- `lib/presentation/pages/editor/widgets/canvas_painter.dart`

**완료 조건:**
- 스트로크가 화면에 즉시 렌더링됨
- 배경 템플릿이 올바르게 표시됨
- 레이어 분리로 불필요한 리페인트 방지

---

### TICKET-008B: 캔버스 위젯 - 타일 캐시
**우선순위:** P0
**예상 시간:** 4시간
**담당:** -

**설명:**
타일 기반 래스터 캐시로 완료된 스트로크 최적화

**작업 내용:**
- [ ] TileCache 클래스 구현
- [ ] 256x256 타일 분할 렌더링
- [ ] LRU 캐시 관리 (100타일)
- [ ] 줌 변경 시 캐시 무효화
- [ ] 스트로크 추가/삭제 시 부분 무효화
- [ ] 성능 테스트

**파일:**
- `lib/domain/services/tile_cache.dart`
- `lib/presentation/pages/editor/widgets/tiled_strokes_widget.dart`

**완료 조건:**
- 1000+ 스트로크에서 60fps 유지
- 줌 변경 시 타일 재생성 < 16ms/타일
- 메모리 사용량 < 50MB (타일 캐시)

---

### TICKET-008C: 캔버스 위젯 - 가변 굵기 렌더링
**우선순위:** P0
**예상 시간:** 3시간
**담당:** -

**설명:**
압력 기반 가변 굵기 메쉬 렌더링

**작업 내용:**
- [ ] MeshStrokePainter 구현
- [ ] Vertices (Triangle Strip) 렌더링
- [ ] 압력 → 굵기 실시간 반영
- [ ] 형광펜/마커 특수 효과
- [ ] GPU 최적화 확인

**파일:**
- `lib/presentation/pages/editor/widgets/mesh_stroke_painter.dart`

**완료 조건:**
- 압력 변화가 자연스럽게 표시됨
- GPU 렌더링으로 CPU 부하 최소화
- 형광펜 반투명 효과 동작

---

### TICKET-009: 펜/터치 입력 분리 (손바닥 거부)
**우선순위:** P0
**예상 시간:** 4시간
**담당:** -

**설명:**
스타일러스 펜과 터치 입력 구분 처리

**작업 내용:**
- [ ] PointerDeviceKind로 펜/터치 구분
- [ ] 펜 입력 시 터치 무시 로직
- [ ] 터치는 줌/팬에만 사용
- [ ] Android S Pen 특수 처리
- [ ] Windows Ink 특수 처리

**파일:**
- `lib/presentation/pages/editor/widgets/canvas_widget.dart`
- `lib/platform/stylus_channel.dart`

**완료 조건:**
- 펜으로 그릴 때 손바닥 터치가 무시됨
- 두 손가락 줌/팬이 정상 동작

---

### TICKET-010: 줌/팬 구현
**우선순위:** P0
**예상 시간:** 3시간
**담당:** -

**설명:**
InteractiveViewer 기반 줌/팬 기능

**작업 내용:**
- [ ] InteractiveViewer 통합
- [ ] 최소/최대 줌 레벨 설정 (0.5x ~ 5x)
- [ ] 줌 레벨에 따른 UI 조정
- [ ] 더블탭 줌 리셋
- [ ] 줌 상태 저장/복원

**파일:**
- `lib/presentation/pages/editor/widgets/canvas_widget.dart`

**완료 조건:**
- 두 손가락으로 줌/팬이 부드럽게 동작
- 펜 입력 중에는 줌/팬 비활성화

---

### TICKET-011: 도구 시스템 (펜/형광펜/지우개)
**우선순위:** P0
**예상 시간:** 5시간
**담당:** -

**설명:**
다양한 필기 도구 구현

**작업 내용:**
- [ ] ToolType enum 정의 (pen, pencil, marker, highlighter, eraser)
- [ ] 펜 도구: 기본 선, 압력 반영
- [ ] 형광펜: 반투명, 넓은 획
- [ ] 지우개: 스트로크 단위 삭제
- [ ] 도구별 렌더링 스타일 적용

**파일:**
- `lib/domain/services/stroke_engine.dart`
- `lib/presentation/pages/editor/widgets/canvas_painter.dart`

**완료 조건:**
- 각 도구가 고유한 스타일로 렌더링됨
- 지우개가 터치한 스트로크를 삭제

---

### TICKET-012: 라쏘 선택 도구
**우선순위:** P0
**예상 시간:** 5시간
**담당:** -

**설명:**
영역 선택 및 조작 도구

**작업 내용:**
- [ ] 라쏘 영역 그리기 모드
- [ ] Path를 사용한 영역 선택 로직
- [ ] 선택된 스트로크 하이라이트
- [ ] 선택 영역 이동/크기조절/복사/삭제
- [ ] 선택 해제 로직

**파일:**
- `lib/domain/services/stroke_engine.dart`
- `lib/presentation/pages/editor/widgets/lasso_widget.dart`

**완료 조건:**
- 라쏘로 그린 영역 내 스트로크가 선택됨
- 선택된 스트로크를 이동/삭제 가능

---

### TICKET-013: 색상/굵기 선택
**우선순위:** P0
**예상 시간:** 3시간
**담당:** -

**설명:**
색상 팔레트 및 굵기 조절 UI

**작업 내용:**
- [ ] 색상 팔레트 위젯 (12색 기본 + 커스텀)
- [ ] 굵기 슬라이더 (1~20)
- [ ] 선택 상태 시각화
- [ ] 최근 사용 색상 저장
- [ ] 커스텀 색상 선택기 (ColorPicker)

**파일:**
- `lib/presentation/pages/editor/widgets/color_picker.dart`
- `lib/presentation/pages/editor/widgets/stroke_width_slider.dart`

**완료 조건:**
- 색상 선택 시 즉시 반영
- 굵기 변경 시 미리보기 표시

---

## Phase 3: 노트 관리 (Week 4)

### TICKET-013: Riverpod Provider 설정
**우선순위:** P0
**예상 시간:** 3시간
**담당:** -

**설명:**
상태 관리 Provider 구조 설정

**작업 내용:**
- [ ] ProviderScope 설정 (main.dart)
- [ ] noteListProvider 구현
- [ ] folderProvider 구현
- [ ] editorProvider 구현
- [ ] settingsProvider 구현

**파일:**
- `lib/presentation/providers/*.dart`

**완료 조건:**
- Provider를 통해 전역 상태 관리됨
- UI에서 상태 변경이 즉시 반영됨

---

### TICKET-014: 홈 화면 UI
**우선순위:** P0
**예상 시간:** 4시간
**담당:** -

**설명:**
앱 시작 화면 구현

**작업 내용:**
- [ ] 홈 화면 레이아웃 구성
- [ ] 빠른 액션 버튼 (새 노트, PDF 열기)
- [ ] 최근 노트 그리드 (썸네일 + 제목 + 날짜)
- [ ] 고정 노트 섹션
- [ ] 검색 버튼

**파일:**
- `lib/presentation/pages/home/home_page.dart`
- `lib/presentation/pages/home/widgets/*.dart`

**완료 조건:**
- 홈 화면이 디자인대로 표시됨
- 노트 탭 시 편집기로 이동

---

### TICKET-015: 라이브러리 화면 UI
**우선순위:** P0
**예상 시간:** 5시간
**담당:** -

**설명:**
노트 라이브러리 (폴더 트리 + 노트 목록)

**작업 내용:**
- [ ] 2단 레이아웃 (좌: 폴더 트리, 우: 노트 그리드)
- [ ] 폴더 트리 위젯 (TreeView)
- [ ] 노트 그리드/리스트 뷰 전환
- [ ] 정렬 옵션 (최근순, 이름순, 생성일순)
- [ ] 폴더/노트 컨텍스트 메뉴 (이름변경, 삭제, 이동)

**파일:**
- `lib/presentation/pages/library/library_page.dart`
- `lib/presentation/pages/library/widgets/folder_tree.dart`
- `lib/presentation/pages/library/widgets/note_grid.dart`

**완료 조건:**
- 폴더 선택 시 해당 노트 표시
- 노트 생성/삭제/이동이 동작

---

### TICKET-016: 편집기 화면 UI
**우선순위:** P0
**예상 시간:** 5시간
**담당:** -

**설명:**
노트 편집기 전체 레이아웃

**작업 내용:**
- [ ] 상단 앱바 (뒤로가기, 제목, 공유/설정)
- [ ] 좌측 페이지 썸네일 사이드바
- [ ] 중앙 캔버스 영역
- [ ] 하단 툴바
- [ ] 노트 제목 편집 기능

**파일:**
- `lib/presentation/pages/editor/editor_page.dart`
- `lib/presentation/pages/editor/widgets/toolbar.dart`
- `lib/presentation/pages/editor/widgets/page_thumbnails.dart`

**완료 조건:**
- 편집기 레이아웃이 완성됨
- 모든 도구가 툴바에서 선택 가능

---

### TICKET-017: 페이지 관리
**우선순위:** P0
**예상 시간:** 3시간
**담당:** -

**설명:**
노트 내 페이지 추가/삭제/이동

**작업 내용:**
- [ ] 페이지 추가 버튼 (+ 템플릿 선택)
- [ ] 페이지 삭제 기능
- [ ] 페이지 순서 변경 (드래그 앤 드롭)
- [ ] 페이지 썸네일 자동 생성
- [ ] 페이지 네비게이션 (이전/다음)

**파일:**
- `lib/presentation/pages/editor/widgets/page_thumbnails.dart`
- `lib/domain/services/note_service.dart`

**완료 조건:**
- 페이지 추가/삭제가 즉시 반영됨
- 페이지 이동 시 순서가 저장됨

---

### TICKET-018: 자동 저장
**우선순위:** P0
**예상 시간:** 2시간
**담당:** -

**설명:**
변경사항 자동 저장 로직

**작업 내용:**
- [ ] 3초 idle 후 자동 저장 (debounce)
- [ ] 저장 중 인디케이터 표시
- [ ] 앱 백그라운드 진입 시 즉시 저장
- [ ] 저장 실패 시 재시도 로직

**파일:**
- `lib/presentation/providers/editor_provider.dart`
- `lib/domain/services/note_service.dart`

**완료 조건:**
- 변경 후 3초 뒤 자동 저장됨
- 저장 상태가 UI에 표시됨

---

### TICKET-019: 검색 기능 (제목/태그)
**우선순위:** P1
**예상 시간:** 3시간
**담당:** -

**설명:**
노트 제목 및 태그 검색

**작업 내용:**
- [ ] 검색 바 UI
- [ ] 제목 검색 쿼리 (SQLite LIKE)
- [ ] 태그 검색 쿼리
- [ ] 검색 결과 하이라이트
- [ ] 최근 검색어 저장

**파일:**
- `lib/presentation/widgets/search_bar.dart`
- `lib/domain/services/search_service.dart`

**완료 조건:**
- 검색어 입력 시 결과가 실시간 필터링됨
- 검색 결과에서 노트 열기 가능

---

## Phase 4: PDF 기능 (Week 5)

### TICKET-020: PDF 가져오기
**우선순위:** P0
**예상 시간:** 3시간
**담당:** -

**설명:**
로컬 PDF 파일 선택 및 가져오기

**작업 내용:**
- [ ] 파일 선택기 구현 (file_picker)
- [ ] PDF 파일 복사 및 저장
- [ ] PDF 메타데이터 추출 (페이지 수, 제목)
- [ ] PDF-노트 연결 생성

**파일:**
- `lib/domain/services/pdf_service.dart`
- `lib/data/datasources/local/file_storage.dart`

**완료 조건:**
- PDF 파일이 앱 내부 저장소에 복사됨
- PDF 정보가 데이터베이스에 저장됨

---

### TICKET-021: PDF 뷰어 구현
**우선순위:** P0
**예상 시간:** 5시간
**담당:** -

**설명:**
PDF 렌더링 및 페이지 네비게이션

**작업 내용:**
- [ ] Syncfusion PDF Viewer 통합
- [ ] 페이지 네비게이션 (썸네일, 페이지 이동)
- [ ] 줌/스크롤 기능
- [ ] 단일 페이지/연속 스크롤 모드
- [ ] 페이지 번호 표시

**파일:**
- `lib/presentation/pages/pdf_viewer/pdf_viewer_page.dart`
- `lib/presentation/pages/pdf_viewer/widgets/pdf_page_list.dart`

**완료 조건:**
- PDF가 선명하게 렌더링됨
- 페이지 이동이 부드러움

---

### TICKET-022: PDF 주석 레이어
**우선순위:** P0
**예상 시간:** 6시간
**담당:** -

**설명:**
PDF 위 필기 주석 기능

**작업 내용:**
- [ ] PDF 페이지 위 투명 캔버스 오버레이
- [ ] 주석 스트로크 저장 (페이지별)
- [ ] PDF 원본 보존 (주석은 별도 저장)
- [ ] 주석 표시/숨기기 토글
- [ ] 주석 지우개 (PDF 내용은 유지)

**파일:**
- `lib/presentation/pages/pdf_viewer/widgets/pdf_annotation_layer.dart`
- `lib/domain/services/pdf_service.dart`

**완료 조건:**
- PDF 위에 자유롭게 필기 가능
- 주석이 PDF 페이지와 정확히 정렬됨
- 원본 PDF는 변경되지 않음

---

### TICKET-023: PDF 내보내기
**우선순위:** P0
**예상 시간:** 4시간
**담당:** -

**설명:**
주석 포함/미포함 PDF 내보내기

**작업 내용:**
- [ ] 주석 포함 PDF 내보내기 (병합)
- [ ] 원본 PDF만 내보내기
- [ ] 내보내기 옵션 다이얼로그
- [ ] 공유 시트 연동 (share_plus)

**파일:**
- `lib/domain/services/export_service.dart`

**완료 조건:**
- 주석이 병합된 PDF가 올바르게 생성됨
- 다른 앱으로 공유 가능

---

## Phase 5: 마무리 (Week 6)

### TICKET-024: 라우팅 설정
**우선순위:** P0
**예상 시간:** 2시간
**담당:** -

**설명:**
go_router 기반 네비게이션

**작업 내용:**
- [ ] 라우트 정의 (홈, 라이브러리, 편집기, PDF뷰어, 설정)
- [ ] 딥링크 처리
- [ ] 뒤로가기 처리
- [ ] 화면 전환 애니메이션

**파일:**
- `lib/presentation/router/app_router.dart`

**완료 조건:**
- 모든 화면 간 네비게이션이 동작
- 시스템 뒤로가기 버튼이 올바르게 동작

---

### TICKET-025: 설정 화면
**우선순위:** P1
**예상 시간:** 3시간
**담당:** -

**설명:**
앱 설정 화면

**작업 내용:**
- [ ] 설정 화면 레이아웃
- [ ] 펜 설정 (기본 색상, 굵기)
- [ ] 기본 템플릿 설정
- [ ] 자동 저장 간격 설정
- [ ] 저장 공간 사용량 표시
- [ ] 앱 정보 / 버전

**파일:**
- `lib/presentation/pages/settings/settings_page.dart`
- `lib/presentation/providers/settings_provider.dart`

**완료 조건:**
- 설정이 저장되고 앱 재시작 후에도 유지됨

---

### TICKET-026: 이미지 내보내기
**우선순위:** P0
**예상 시간:** 2시간
**담당:** -

**설명:**
노트 페이지를 PNG 이미지로 내보내기

**작업 내용:**
- [ ] 캔버스를 이미지로 변환
- [ ] 해상도 옵션 (1x, 2x, 3x)
- [ ] 배경 포함/투명 옵션
- [ ] 갤러리 저장 / 공유

**파일:**
- `lib/domain/services/export_service.dart`

**완료 조건:**
- PNG 이미지가 고품질로 생성됨
- 갤러리에 저장되거나 공유 가능

---

### TICKET-027: 수동 백업/복원
**우선순위:** P0
**예상 시간:** 3시간
**담당:** -

**설명:**
노트 데이터 백업 및 복원

**작업 내용:**
- [ ] 전체 데이터 ZIP 내보내기
- [ ] 특정 노트 JSON 내보내기
- [ ] ZIP/JSON 가져오기 및 복원
- [ ] 중복 노트 처리 (덮어쓰기/건너뛰기)

**파일:**
- `lib/domain/services/backup_service.dart`

**완료 조건:**
- 백업 파일 생성 및 복원이 동작
- 복원 후 노트가 원본과 동일

---

### TICKET-028: 성능 최적화
**우선순위:** P1
**예상 시간:** 4시간
**담당:** -

**설명:**
렌더링 및 메모리 최적화

**작업 내용:**
- [ ] 레이어 분리 (RepaintBoundary)
- [ ] 가상화 렌더링 (화면 밖 스트로크 스킵)
- [ ] 페이지 단위 메모리 관리
- [ ] 대용량 노트 테스트 (5000+ 스트로크)
- [ ] 메모리 프로파일링

**파일:**
- 다수 파일 수정

**완료 조건:**
- 5000개 스트로크에서 60fps 유지
- 메모리 사용량 100MB 이하

---

### TICKET-029: 버그 수정 및 QA
**우선순위:** P0
**예상 시간:** 8시간
**담당:** -

**설명:**
전체 기능 테스트 및 버그 수정

**작업 내용:**
- [ ] 전체 기능 체크리스트 테스트
- [ ] 엣지 케이스 테스트
- [ ] Android/Windows 플랫폼별 테스트
- [ ] 다양한 기기 해상도 테스트
- [ ] 발견된 버그 수정

**완료 조건:**
- 치명적 버그 0개
- 모든 핵심 기능이 안정적으로 동작

---

### TICKET-030: 배포 준비
**우선순위:** P0
**예상 시간:** 3시간
**담당:** -

**설명:**
앱 배포를 위한 준비 작업

**작업 내용:**
- [ ] 앱 아이콘 생성 (Android/Windows)
- [ ] 스플래시 화면 설정
- [ ] 앱 서명 키 생성 (Android)
- [ ] Release 빌드 테스트
- [ ] README.md 작성

**파일:**
- `android/app/src/main/res/`
- `windows/runner/resources/`

**완료 조건:**
- Release APK/exe가 정상 빌드됨
- 앱 아이콘이 올바르게 표시됨

---

## Phase 2 티켓 (차후 개발)

### TICKET-P2-001: 계정 시스템
**우선순위:** P2
**설명:** Google/이메일 로그인 구현

### TICKET-P2-002: 클라우드 동기화
**우선순위:** P2
**설명:** Firebase 기반 실시간 동기화

### TICKET-P2-003: OCR 검색
**우선순위:** P2
**설명:** ML Kit 기반 필기 인식 검색

### TICKET-P2-004: AI 요약
**우선순위:** P2
**설명:** Claude API 연동 자동 요약

### TICKET-P2-005: 녹음 동기화
**우선순위:** P2
**설명:** 녹음 타임라인과 필기 매칭

### TICKET-P2-006: 템플릿 마켓
**우선순위:** P2
**설명:** 커뮤니티 템플릿 공유

### TICKET-P2-007: 협업 기능
**우선순위:** P2
**설명:** 실시간 공동 편집

### TICKET-P2-008: 홈화면 위젯
**우선순위:** P2
**설명:** Android/Windows 위젯

---

## 티켓 상태 요약

### Phase 0 (PoC) - 2-4일
| 티켓 | 설명 | 예상 시간 | 상태 |
|------|------|----------|------|
| TICKET-000 | PoC 프로젝트 생성 | 1h | ☐ |
| TICKET-001A | 펜/터치 분리 검증 | 2h | ☐ |
| TICKET-001B | 입력 지연 측정 | 2h | ☐ |
| TICKET-001C | 기본 스트로크 렌더링 | 3h | ☐ |
| TICKET-001D | PoC 평가 및 Go/No-Go | 2h | ☐ |

### Phase 1 (기반) - Week 1
| 티켓 | 설명 | 예상 시간 | 상태 |
|------|------|----------|------|
| TICKET-002 | 프로젝트 초기화 | 2h | ☐ |
| TICKET-003 | 데이터 모델 정의 | 3h | ☐ |
| TICKET-004 | 로컬 데이터베이스 설정 | 4h | ☐ |
| TICKET-005 | 바이너리 스트로크 저장소 | 4h | ☐ |
| TICKET-006 | 레포지토리 구현 | 4h | ☐ |

### Phase 2 (필기 엔진) - Week 2-3
| 티켓 | 설명 | 예상 시간 | 상태 |
|------|------|----------|------|
| TICKET-007A | 스트로크 엔진 - 입력 파이프라인 | 4h | ☐ |
| TICKET-007B | 스트로크 엔진 - 스무딩 & 메쉬 | 4h | ☐ |
| TICKET-007C | 스트로크 엔진 - 공간 인덱스 | 3h | ☐ |
| TICKET-008A | 캔버스 위젯 - 기본 렌더링 | 4h | ☐ |
| TICKET-008B | 캔버스 위젯 - 타일 캐시 | 4h | ☐ |
| TICKET-008C | 캔버스 위젯 - 가변 굵기 | 3h | ☐ |
| TICKET-009 | 펜/터치 입력 분리 | 4h | ☐ |
| TICKET-010 | 줌/팬 구현 | 3h | ☐ |
| TICKET-011 | 도구 시스템 | 5h | ☐ |
| TICKET-012 | 라쏘 선택 도구 | 5h | ☐ |
| TICKET-013 | 색상/굵기 선택 | 3h | ☐ |

### 전체 요약

| 상태 | 개수 |
|------|------|
| Phase 0 티켓 | 5 |
| Phase 1 티켓 | 5 |
| Phase 2 티켓 | 11 |
| Phase 3 티켓 | 6 |
| Phase 4 티켓 | 4 |
| Phase 5 티켓 | 7 |
| **총 MVP 티켓** | **38** |
| Phase 2 (차후) | 8 |

**총 예상 시간:** ~130시간
- Phase 0: ~10시간 (2-4일)
- Phase 1-5 MVP: ~120시간 (약 6주, 1일 4시간 기준)

---

*이 문서는 개발 진행에 따라 업데이트됩니다.*
