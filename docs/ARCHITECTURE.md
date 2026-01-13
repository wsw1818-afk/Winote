# Winote 기술 아키텍처

> Flutter 기반 크로스플랫폼 필기 앱 아키텍처 설계

---

## 1. 시스템 개요

### 1.1 아키텍처 다이어그램

```
┌─────────────────────────────────────────────────────────────────────┐
│                           클라이언트 앱                              │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    Presentation Layer                        │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐           │   │
│  │  │  Home   │ │ Library │ │ Editor  │ │PDF Viewer│           │   │
│  │  │  Page   │ │  Page   │ │  Page   │ │  Page   │           │   │
│  │  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘           │   │
│  │       │           │           │           │                 │   │
│  │  ┌────┴───────────┴───────────┴───────────┴────┐           │   │
│  │  │              State Management               │           │   │
│  │  │         (Riverpod Providers)                │           │   │
│  │  └────────────────────┬────────────────────────┘           │   │
│  └───────────────────────┼─────────────────────────────────────┘   │
│                          │                                         │
│  ┌───────────────────────┼─────────────────────────────────────┐   │
│  │                    Domain Layer                              │   │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐            │   │
│  │  │ NoteService │ │StrokeEngine │ │ PDFService  │            │   │
│  │  └──────┬──────┘ └──────┬──────┘ └──────┬──────┘            │   │
│  │         │               │               │                    │   │
│  │  ┌──────┴───────────────┴───────────────┴──────┐            │   │
│  │  │              Repository Layer               │            │   │
│  │  │   (NoteRepo, StrokeRepo, PDFRepo)          │            │   │
│  │  └────────────────────┬────────────────────────┘            │   │
│  └───────────────────────┼─────────────────────────────────────┘   │
│                          │                                         │
│  ┌───────────────────────┼─────────────────────────────────────┐   │
│  │                     Data Layer                               │   │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐         │   │
│  │  │   SQLite     │ │  Binary File │ │   Folder     │         │   │
│  │  │  (drift)     │ │  (.strokes)  │ │   Sync       │         │   │
│  │  │  메타데이터   │ │  스트로크    │ │  (OneDrive)  │         │   │
│  │  └──────────────┘ └──────────────┘ └──────────────┘         │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                  Platform Channel                            │   │
│  │  ┌──────────────────┐ ┌──────────────────┐                  │   │
│  │  │   Android        │ │   Windows        │                  │   │
│  │  │   (S Pen API)    │ │   (Windows Ink)  │                  │   │
│  │  └──────────────────┘ └──────────────────┘                  │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼ (Phase 2 - 서버 동기화)
┌─────────────────────────────────────────────────────────────────────┐
│                           백엔드 서버                                │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐                │
│  │   Auth API   │ │   Sync API   │ │   AI API     │                │
│  │  (Firebase)  │ │  (WebSocket) │ │  (Claude)    │                │
│  └──────────────┘ └──────────────┘ └──────────────┘                │
│                          │                                          │
│  ┌───────────────────────┴─────────────────────────────────────┐   │
│  │                     Cloud Storage                            │   │
│  │  ┌──────────────┐ ┌──────────────┐                          │   │
│  │  │   Firestore  │ │ Cloud Storage│                          │   │
│  │  │   (메타데이터) │ │   (파일)     │                          │   │
│  │  └──────────────┘ └──────────────┘                          │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### 1.2 계층 설명

| 계층 | 역할 | 주요 컴포넌트 |
|------|------|--------------|
| **Presentation** | UI 렌더링, 사용자 입력 처리 | Pages, Widgets, Providers |
| **Domain** | 비즈니스 로직, 유스케이스 | Services, Entities, UseCases |
| **Data** | 데이터 접근, 영속성 | Repositories, DataSources |
| **Platform** | 네이티브 기능 연동 | Platform Channels |

---

## 2. 폴더 구조

```
lib/
├── main.dart                      # 앱 진입점
├── app.dart                       # MaterialApp 설정
│
├── core/                          # 공통 유틸리티
│   ├── constants/
│   │   ├── app_constants.dart     # 앱 상수
│   │   ├── colors.dart            # 색상 정의
│   │   └── dimensions.dart        # 크기 상수
│   ├── extensions/
│   │   ├── context_extension.dart
│   │   └── string_extension.dart
│   ├── utils/
│   │   ├── file_utils.dart
│   │   ├── date_utils.dart
│   │   └── logger.dart
│   └── errors/
│       ├── app_exception.dart
│       └── failure.dart
│
├── data/                          # 데이터 계층
│   ├── datasources/
│   │   ├── local/
│   │   │   ├── database/
│   │   │   │   ├── app_database.dart      # Drift 데이터베이스
│   │   │   │   ├── tables/
│   │   │   │   │   ├── notes_table.dart
│   │   │   │   │   ├── pages_table.dart
│   │   │   │   │   └── folders_table.dart
│   │   │   │   └── daos/
│   │   │   │       ├── note_dao.dart
│   │   │   │       └── folder_dao.dart
│   │   │   ├── file_storage.dart          # 파일 저장
│   │   │   └── preferences_storage.dart   # 설정 저장
│   │   └── remote/                        # (Phase 2)
│   │       ├── sync_api.dart
│   │       └── ai_api.dart
│   ├── models/                    # 데이터 모델 (DTO)
│   │   ├── note_model.dart
│   │   ├── page_model.dart
│   │   ├── stroke_model.dart
│   │   └── folder_model.dart
│   └── repositories/              # 레포지토리 구현체
│       ├── note_repository_impl.dart
│       ├── stroke_repository_impl.dart
│       └── folder_repository_impl.dart
│
├── domain/                        # 도메인 계층
│   ├── entities/                  # 비즈니스 엔티티
│   │   ├── note.dart
│   │   ├── page.dart
│   │   ├── stroke.dart
│   │   ├── stroke_point.dart
│   │   └── folder.dart
│   ├── repositories/              # 레포지토리 인터페이스
│   │   ├── note_repository.dart
│   │   ├── stroke_repository.dart
│   │   └── folder_repository.dart
│   ├── services/                  # 비즈니스 서비스
│   │   ├── note_service.dart
│   │   ├── stroke_engine.dart     # 필기 엔진
│   │   ├── pdf_service.dart
│   │   └── export_service.dart
│   └── usecases/                  # 유스케이스 (선택)
│       ├── create_note.dart
│       ├── save_stroke.dart
│       └── export_pdf.dart
│
├── presentation/                  # 프레젠테이션 계층
│   ├── providers/                 # Riverpod Providers
│   │   ├── note_provider.dart
│   │   ├── editor_provider.dart
│   │   ├── folder_provider.dart
│   │   └── settings_provider.dart
│   ├── pages/                     # 페이지 (화면)
│   │   ├── home/
│   │   │   ├── home_page.dart
│   │   │   └── widgets/
│   │   │       ├── recent_notes_grid.dart
│   │   │       └── quick_actions.dart
│   │   ├── library/
│   │   │   ├── library_page.dart
│   │   │   └── widgets/
│   │   │       ├── folder_tree.dart
│   │   │       └── note_grid.dart
│   │   ├── editor/
│   │   │   ├── editor_page.dart
│   │   │   └── widgets/
│   │   │       ├── canvas_widget.dart
│   │   │       ├── toolbar.dart
│   │   │       ├── page_thumbnails.dart
│   │   │       └── color_picker.dart
│   │   ├── pdf_viewer/
│   │   │   ├── pdf_viewer_page.dart
│   │   │   └── widgets/
│   │   │       └── pdf_annotation_layer.dart
│   │   └── settings/
│   │       └── settings_page.dart
│   ├── widgets/                   # 공통 위젯
│   │   ├── note_card.dart
│   │   ├── loading_overlay.dart
│   │   └── empty_state.dart
│   └── router/                    # 라우팅
│       └── app_router.dart
│
├── platform/                      # 플랫폼 채널
│   ├── stylus_channel.dart        # 펜 입력 채널
│   └── file_picker_channel.dart   # 파일 선택 채널
│
└── l10n/                          # 다국어 (Phase 2)
    ├── app_en.arb
    └── app_ko.arb

android/
├── app/src/main/kotlin/com/winote/
│   ├── MainActivity.kt
│   └── StylusPlugin.kt            # S Pen 네이티브 구현

windows/
├── runner/
│   └── flutter_window.cpp
└── winote_plugin/
    └── windows_ink_plugin.cpp     # Windows Ink 네이티브 구현
```

---

## 3. 핵심 컴포넌트 상세

### 3.1 스트로크 엔진 파이프라인 (핵심)

상업용 필기감을 위한 전체 스트로크 처리 파이프라인입니다.

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Stroke Engine Pipeline                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────┐   ┌──────────┐   ┌────────┐   ┌───────────┐          │
│  │  Input  │──▶│ Resample │──▶│ Filter │──▶│ Smoothing │          │
│  │ (Stylus)│   │(간격보정) │   │(Kalman)│   │ (Bezier)  │          │
│  └─────────┘   └──────────┘   └────────┘   └─────┬─────┘          │
│                                                   │                 │
│                                                   ▼                 │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    Mesh Generation                           │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │  Pressure → Width Mapping (가변 굵기)                  │   │   │
│  │  │  Tilt → Angle Mapping (기울기 반영)                    │   │   │
│  │  │  Triangle Strip 생성 (GPU 최적화)                     │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                   │                 │
│                                                   ▼                 │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                      Render Layer                            │   │
│  │                                                               │   │
│  │  ┌─────────────────┐  ┌──────────────────────────────────┐  │   │
│  │  │  Active Stroke  │  │     Committed Strokes            │  │   │
│  │  │  (Vector/Mesh)  │  │  ┌─────────────────────────────┐ │  │   │
│  │  │  실시간 렌더링   │  │  │   Tile-based Raster Cache  │ │  │   │
│  │  └─────────────────┘  │  │   (256x256px 타일)           │ │  │   │
│  │                       │  │   줌 변경 시 재생성           │ │  │   │
│  │                       │  └─────────────────────────────┘ │  │   │
│  │                       └──────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    Spatial Index                             │   │
│  │  QuadTree for Viewport Query (뷰포트 최적화)                  │   │
│  │  - O(log n) 조회 성능                                        │   │
│  │  - 화면 밖 스트로크 자동 제외                                 │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

#### 3.1.1 파이프라인 단계별 설명

| 단계 | 목적 | 알고리즘 |
|------|------|---------|
| **Input** | 펜 입력 수집 | PointerEvent → (x, y, pressure, tilt, timestamp) |
| **Resample** | 간격 보정 | 2-3px 간격으로 재샘플링, 속도 기반 적응형 |
| **Filter** | 노이즈 제거 | Kalman Filter 또는 1-Euro Filter |
| **Smoothing** | 곡선화 | Catmull-Rom Spline → Bezier 변환 |
| **Mesh Gen** | 가변 굵기 | Pressure/Tilt → Width, Triangle Strip |
| **Render** | 화면 출력 | Active=Vector, Committed=Raster Cache |

#### 3.1.2 성능 목표

| 지표 | 목표값 | 측정 방법 |
|------|--------|----------|
| **입력 지연** | < 10ms | Stylus 터치 → 첫 픽셀 출력 |
| **프레임 레이트** | 60fps | 1000+ 스트로크 상태에서 |
| **메모리** | < 100MB | 10페이지 노트 기준 |

### 3.2 스트로크 엔진 구현 (StrokeEngine)

필기 앱의 핵심인 스트로크 처리 엔진입니다.

```dart
// domain/services/stroke_engine.dart

import 'dart:ui';
import 'dart:math' as math;
import '../entities/stroke.dart';
import '../entities/stroke_point.dart';
import '../entities/bounding_box.dart';
import 'spatial_index.dart';

enum ToolType { pen, pencil, marker, highlighter, eraser }

class StrokeEngine {
  // 현재 진행 중인 스트로크
  Stroke? _currentStroke;

  // 완료된 스트로크 목록
  final List<Stroke> _strokes = [];

  // 공간 인덱스 (QuadTree)
  late QuadTree _spatialIndex;

  // 실행취소/재실행 스택
  final List<StrokeAction> _undoStack = [];
  final List<StrokeAction> _redoStack = [];

  // 현재 도구 설정
  ToolType currentTool = ToolType.pen;
  Color currentColor = const Color(0xFF000000);
  double currentWidth = 2.0;

  // 필터 상태 (Kalman/1-Euro)
  late OneEuroFilter _xFilter;
  late OneEuroFilter _yFilter;
  late OneEuroFilter _pressureFilter;

  // 설정
  static const double _resampleDistance = 2.5; // 재샘플링 간격 (px)
  static const double _minPointDistance = 1.0; // 최소 포인트 간격

  StrokeEngine() {
    _spatialIndex = QuadTree(
      bounds: const Rect.fromLTWH(0, 0, 10000, 10000),
      maxDepth: 8,
      maxObjects: 10,
    );
    _initFilters();
  }

  void _initFilters() {
    // 1-Euro Filter 초기화 (노이즈 제거용)
    _xFilter = OneEuroFilter(minCutoff: 1.0, beta: 0.007, dCutoff: 1.0);
    _yFilter = OneEuroFilter(minCutoff: 1.0, beta: 0.007, dCutoff: 1.0);
    _pressureFilter = OneEuroFilter(minCutoff: 1.0, beta: 0.001, dCutoff: 1.0);
  }

  /// 스트로크 시작 (펜 터치 시작)
  void startStroke(Offset position, double pressure, double tilt) {
    _initFilters(); // 필터 초기화

    final filteredX = _xFilter.filter(position.dx, DateTime.now().millisecondsSinceEpoch / 1000.0);
    final filteredY = _yFilter.filter(position.dy, DateTime.now().millisecondsSinceEpoch / 1000.0);
    final filteredPressure = _pressureFilter.filter(pressure, DateTime.now().millisecondsSinceEpoch / 1000.0);

    _currentStroke = Stroke(
      id: _generateId(),
      toolType: currentTool,
      color: currentColor,
      width: currentWidth,
      points: [
        StrokePoint(
          x: filteredX,
          y: filteredY,
          pressure: filteredPressure,
          tilt: tilt,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      ],
      boundingBox: BoundingBox(
        minX: filteredX,
        minY: filteredY,
        maxX: filteredX,
        maxY: filteredY,
      ),
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 스트로크 계속 (펜 이동 중) - 파이프라인 적용
  void continueStroke(Offset position, double pressure, double tilt) {
    if (_currentStroke == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. Filter 단계: 노이즈 제거
    final filteredX = _xFilter.filter(position.dx, now / 1000.0);
    final filteredY = _yFilter.filter(position.dy, now / 1000.0);
    final filteredPressure = _pressureFilter.filter(pressure, now / 1000.0);

    // 2. Resample 단계: 최소 간격 체크
    if (_currentStroke!.points.isNotEmpty) {
      final lastPoint = _currentStroke!.points.last;
      final distance = _distance2D(lastPoint.x, lastPoint.y, filteredX, filteredY);
      if (distance < _minPointDistance) return; // 너무 가까우면 스킵
    }

    // 3. 포인트 추가
    final newPoint = StrokePoint(
      x: filteredX,
      y: filteredY,
      pressure: filteredPressure,
      tilt: tilt,
      timestamp: now,
    );
    _currentStroke!.points.add(newPoint);

    // 4. BoundingBox 업데이트
    _currentStroke!.boundingBox.expand(filteredX, filteredY);
  }

  /// 스트로크 종료 (펜 떼기)
  Stroke? endStroke() {
    if (_currentStroke == null) return null;

    final stroke = _currentStroke!;

    // 포인트가 너무 적으면 무시
    if (stroke.points.length < 2) {
      _currentStroke = null;
      return null;
    }

    // 1. Resample: 균일한 간격으로 재샘플링
    _resampleStroke(stroke);

    // 2. Smoothing: 베지어 스무딩 적용
    _smoothStroke(stroke);

    // 3. BoundingBox 최종 계산
    stroke.boundingBox = _calculateBoundingBox(stroke.points);

    // 4. 스트로크 저장 및 공간 인덱스 업데이트
    _strokes.add(stroke);
    _spatialIndex.insert(stroke);

    // 5. Undo 스택 업데이트
    _undoStack.add(StrokeAction.add(stroke));
    _redoStack.clear();

    _currentStroke = null;
    return stroke;
  }

  /// 뷰포트 내 스트로크 조회 (O(log n) 성능)
  List<Stroke> getStrokesInViewport(Rect viewport) {
    return _spatialIndex.query(viewport);
  }

  /// 실행취소
  Stroke? undo() {
    if (_undoStack.isEmpty) return null;

    final action = _undoStack.removeLast();
    _redoStack.add(action);

    if (action.type == ActionType.add) {
      _strokes.remove(action.stroke);
      _spatialIndex.remove(action.stroke);
      return action.stroke;
    }
    return null;
  }

  /// 재실행
  Stroke? redo() {
    if (_redoStack.isEmpty) return null;

    final action = _redoStack.removeLast();
    _undoStack.add(action);

    if (action.type == ActionType.add) {
      _strokes.add(action.stroke);
      _spatialIndex.insert(action.stroke);
      return action.stroke;
    }
    return null;
  }

  /// 영역 내 스트로크 선택 (라쏘) - 공간 인덱스 활용
  List<Stroke> selectStrokesInPath(Path selectionPath) {
    final bounds = selectionPath.getBounds();
    final candidates = _spatialIndex.query(bounds);

    return candidates.where((stroke) {
      return stroke.points.any((point) {
        return selectionPath.contains(Offset(point.x, point.y));
      });
    }).toList();
  }

  /// 재샘플링: 균일한 간격으로 포인트 재배치
  void _resampleStroke(Stroke stroke) {
    if (stroke.points.length < 3) return;

    final resampledPoints = <StrokePoint>[];
    resampledPoints.add(stroke.points.first);

    double accumulatedDistance = 0;

    for (int i = 1; i < stroke.points.length; i++) {
      final prev = stroke.points[i - 1];
      final curr = stroke.points[i];
      final segmentDistance = _distance2D(prev.x, prev.y, curr.x, curr.y);

      accumulatedDistance += segmentDistance;

      if (accumulatedDistance >= _resampleDistance) {
        // 보간하여 새 포인트 생성
        final t = (accumulatedDistance - _resampleDistance) / segmentDistance;
        resampledPoints.add(StrokePoint(
          x: prev.x + (curr.x - prev.x) * (1 - t),
          y: prev.y + (curr.y - prev.y) * (1 - t),
          pressure: prev.pressure + (curr.pressure - prev.pressure) * (1 - t),
          tilt: prev.tilt + (curr.tilt - prev.tilt) * (1 - t),
          timestamp: (prev.timestamp + curr.timestamp) ~/ 2,
        ));
        accumulatedDistance = segmentDistance * t;
      }
    }

    resampledPoints.add(stroke.points.last);

    stroke.points
      ..clear()
      ..addAll(resampledPoints);
  }

  /// 스트로크 스무딩 (Catmull-Rom → Bezier)
  void _smoothStroke(Stroke stroke) {
    if (stroke.points.length < 4) return;

    final smoothedPoints = <StrokePoint>[];
    smoothedPoints.add(stroke.points.first);

    // Catmull-Rom 스플라인 보간
    for (int i = 1; i < stroke.points.length - 2; i++) {
      final p0 = stroke.points[i - 1];
      final p1 = stroke.points[i];
      final p2 = stroke.points[i + 1];
      final p3 = stroke.points[i + 2];

      // 중간점 보간 (t = 0.5)
      smoothedPoints.add(p1);
      smoothedPoints.add(_catmullRomInterpolate(p0, p1, p2, p3, 0.5));
    }

    smoothedPoints.add(stroke.points[stroke.points.length - 2]);
    smoothedPoints.add(stroke.points.last);

    stroke.points
      ..clear()
      ..addAll(smoothedPoints);
  }

  StrokePoint _catmullRomInterpolate(
    StrokePoint p0, StrokePoint p1, StrokePoint p2, StrokePoint p3, double t) {
    final t2 = t * t;
    final t3 = t2 * t;

    final x = 0.5 * ((2 * p1.x) +
        (-p0.x + p2.x) * t +
        (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 +
        (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3);

    final y = 0.5 * ((2 * p1.y) +
        (-p0.y + p2.y) * t +
        (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 +
        (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3);

    final pressure = (p1.pressure + p2.pressure) / 2;
    final tilt = (p1.tilt + p2.tilt) / 2;

    return StrokePoint(
      x: x,
      y: y,
      pressure: pressure,
      tilt: tilt,
      timestamp: (p1.timestamp + p2.timestamp) ~/ 2,
    );
  }

  BoundingBox _calculateBoundingBox(List<StrokePoint> points) {
    if (points.isEmpty) {
      return BoundingBox(minX: 0, minY: 0, maxX: 0, maxY: 0);
    }

    double minX = points.first.x;
    double minY = points.first.y;
    double maxX = points.first.x;
    double maxY = points.first.y;

    for (final point in points) {
      if (point.x < minX) minX = point.x;
      if (point.y < minY) minY = point.y;
      if (point.x > maxX) maxX = point.x;
      if (point.y > maxY) maxY = point.y;
    }

    return BoundingBox(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  double _distance2D(double x1, double y1, double x2, double y2) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    return math.sqrt(dx * dx + dy * dy);
  }

  String _generateId() => DateTime.now().microsecondsSinceEpoch.toString();
}

/// 1-Euro Filter: 적응형 노이즈 필터
class OneEuroFilter {
  final double minCutoff;
  final double beta;
  final double dCutoff;

  double _xPrev = 0;
  double _dxPrev = 0;
  double _tPrev = 0;
  bool _initialized = false;

  OneEuroFilter({
    required this.minCutoff,
    required this.beta,
    required this.dCutoff,
  });

  double filter(double x, double t) {
    if (!_initialized) {
      _xPrev = x;
      _tPrev = t;
      _initialized = true;
      return x;
    }

    final dt = t - _tPrev;
    if (dt <= 0) return _xPrev;

    final dx = (x - _xPrev) / dt;
    final edx = _lowPassFilter(dx, _dxPrev, _alpha(dt, dCutoff));
    _dxPrev = edx;

    final cutoff = minCutoff + beta * edx.abs();
    final result = _lowPassFilter(x, _xPrev, _alpha(dt, cutoff));

    _xPrev = result;
    _tPrev = t;

    return result;
  }

  double _alpha(double dt, double cutoff) {
    final tau = 1.0 / (2 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }

  double _lowPassFilter(double x, double xPrev, double alpha) {
    return alpha * x + (1 - alpha) * xPrev;
  }
}

// 스트로크 액션 (실행취소/재실행용)
enum ActionType { add, remove }

class StrokeAction {
  final ActionType type;
  final Stroke stroke;

  StrokeAction.add(this.stroke) : type = ActionType.add;
  StrokeAction.remove(this.stroke) : type = ActionType.remove;
}

/// BoundingBox: 스트로크 영역 정의
class BoundingBox {
  double minX;
  double minY;
  double maxX;
  double maxY;

  BoundingBox({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });

  Rect toRect() => Rect.fromLTRB(minX, minY, maxX, maxY);

  void expand(double x, double y) {
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
  }

  bool overlaps(Rect rect) {
    return !(maxX < rect.left ||
        minX > rect.right ||
        maxY < rect.top ||
        minY > rect.bottom);
  }
}
```

### 3.3 공간 인덱스 (QuadTree)

뷰포트 쿼리를 O(log n) 성능으로 최적화합니다.

```dart
// domain/services/spatial_index.dart

class QuadTree {
  final Rect bounds;
  final int maxDepth;
  final int maxObjects;
  final int _depth;

  List<Stroke> _objects = [];
  List<QuadTree>? _children;

  QuadTree({
    required this.bounds,
    this.maxDepth = 8,
    this.maxObjects = 10,
    int depth = 0,
  }) : _depth = depth;

  /// 스트로크 삽입
  void insert(Stroke stroke) {
    // 바운딩박스가 영역과 겹치지 않으면 무시
    if (!stroke.boundingBox.overlaps(bounds)) return;

    // 자식 노드가 있으면 자식에 삽입 시도
    if (_children != null) {
      for (final child in _children!) {
        child.insert(stroke);
      }
      return;
    }

    // 객체 추가
    _objects.add(stroke);

    // 분할 필요 여부 확인
    if (_objects.length > maxObjects && _depth < maxDepth) {
      _subdivide();

      // 기존 객체들을 자식 노드로 재분배
      final oldObjects = _objects;
      _objects = [];
      for (final obj in oldObjects) {
        for (final child in _children!) {
          child.insert(obj);
        }
      }
    }
  }

  /// 영역 쿼리: 뷰포트와 겹치는 스트로크 반환
  List<Stroke> query(Rect viewport) {
    final result = <Stroke>[];

    // 영역이 겹치지 않으면 빈 결과
    if (!_overlaps(viewport)) return result;

    // 현재 노드의 객체 중 뷰포트와 겹치는 것 추가
    for (final stroke in _objects) {
      if (stroke.boundingBox.overlaps(viewport)) {
        result.add(stroke);
      }
    }

    // 자식 노드 쿼리
    if (_children != null) {
      for (final child in _children!) {
        result.addAll(child.query(viewport));
      }
    }

    return result;
  }

  /// 스트로크 제거
  bool remove(Stroke stroke) {
    // 현재 노드에서 제거 시도
    if (_objects.remove(stroke)) return true;

    // 자식 노드에서 제거 시도
    if (_children != null) {
      for (final child in _children!) {
        if (child.remove(stroke)) return true;
      }
    }

    return false;
  }

  /// 전체 초기화
  void clear() {
    _objects.clear();
    _children = null;
  }

  void _subdivide() {
    final halfWidth = bounds.width / 2;
    final halfHeight = bounds.height / 2;
    final x = bounds.left;
    final y = bounds.top;

    _children = [
      QuadTree(
        bounds: Rect.fromLTWH(x, y, halfWidth, halfHeight),
        maxDepth: maxDepth,
        maxObjects: maxObjects,
        depth: _depth + 1,
      ),
      QuadTree(
        bounds: Rect.fromLTWH(x + halfWidth, y, halfWidth, halfHeight),
        maxDepth: maxDepth,
        maxObjects: maxObjects,
        depth: _depth + 1,
      ),
      QuadTree(
        bounds: Rect.fromLTWH(x, y + halfHeight, halfWidth, halfHeight),
        maxDepth: maxDepth,
        maxObjects: maxObjects,
        depth: _depth + 1,
      ),
      QuadTree(
        bounds: Rect.fromLTWH(x + halfWidth, y + halfHeight, halfWidth, halfHeight),
        maxDepth: maxDepth,
        maxObjects: maxObjects,
        depth: _depth + 1,
      ),
    ];
  }

  bool _overlaps(Rect rect) {
    return !(bounds.right < rect.left ||
        bounds.left > rect.right ||
        bounds.bottom < rect.top ||
        bounds.top > rect.bottom);
  }
}
```

### 3.4 타일 기반 래스터 캐시 (TileCache)

완료된 스트로크를 타일 단위로 캐시하여 렌더링 성능을 최적화합니다.

```dart
// domain/services/tile_cache.dart

import 'dart:ui' as ui;

class TileCache {
  static const int tileSize = 256; // 256x256 픽셀
  static const int maxCachedTiles = 100; // LRU 캐시 크기

  final Map<TileKey, CachedTile> _cache = {};
  final List<TileKey> _lruOrder = [];
  double _currentZoom = 1.0;

  /// 줌 레벨 변경 시 캐시 무효화
  void setZoom(double zoom) {
    if ((zoom - _currentZoom).abs() > 0.01) {
      _currentZoom = zoom;
      invalidateAll(); // 줌 변경 시 전체 무효화
    }
  }

  /// 타일 조회 또는 생성
  Future<ui.Image?> getTile(
    int tileX,
    int tileY,
    List<Stroke> strokes,
    Future<ui.Image> Function(Rect tileBounds, List<Stroke> strokes) renderer,
  ) async {
    final key = TileKey(tileX, tileY, _currentZoom);

    // 캐시 히트
    if (_cache.containsKey(key)) {
      _updateLRU(key);
      return _cache[key]!.image;
    }

    // 캐시 미스: 타일 렌더링
    final tileBounds = Rect.fromLTWH(
      tileX * tileSize / _currentZoom,
      tileY * tileSize / _currentZoom,
      tileSize / _currentZoom,
      tileSize / _currentZoom,
    );

    // 타일 영역과 겹치는 스트로크만 필터링
    final relevantStrokes = strokes.where((s) =>
        s.boundingBox.overlaps(tileBounds)).toList();

    if (relevantStrokes.isEmpty) {
      return null; // 빈 타일
    }

    final image = await renderer(tileBounds, relevantStrokes);

    // LRU 캐시 관리
    if (_cache.length >= maxCachedTiles) {
      _evictOldest();
    }

    _cache[key] = CachedTile(image: image, timestamp: DateTime.now());
    _lruOrder.add(key);

    return image;
  }

  /// 특정 영역의 타일 무효화 (스트로크 추가/삭제 시)
  void invalidateRegion(BoundingBox region) {
    final minTileX = (region.minX * _currentZoom / tileSize).floor();
    final maxTileX = (region.maxX * _currentZoom / tileSize).ceil();
    final minTileY = (region.minY * _currentZoom / tileSize).floor();
    final maxTileY = (region.maxY * _currentZoom / tileSize).ceil();

    final keysToRemove = <TileKey>[];
    for (final key in _cache.keys) {
      if (key.x >= minTileX && key.x <= maxTileX &&
          key.y >= minTileY && key.y <= maxTileY) {
        keysToRemove.add(key);
      }
    }

    for (final key in keysToRemove) {
      _cache.remove(key);
      _lruOrder.remove(key);
    }
  }

  /// 전체 캐시 무효화
  void invalidateAll() {
    _cache.clear();
    _lruOrder.clear();
  }

  void _updateLRU(TileKey key) {
    _lruOrder.remove(key);
    _lruOrder.add(key);
  }

  void _evictOldest() {
    if (_lruOrder.isNotEmpty) {
      final oldestKey = _lruOrder.removeAt(0);
      _cache.remove(oldestKey);
    }
  }
}

class TileKey {
  final int x;
  final int y;
  final double zoom;

  TileKey(this.x, this.y, this.zoom);

  @override
  bool operator ==(Object other) =>
      other is TileKey && x == other.x && y == other.y &&
      (zoom - other.zoom).abs() < 0.001;

  @override
  int get hashCode => Object.hash(x, y, (zoom * 1000).round());
}

class CachedTile {
  final ui.Image image;
  final DateTime timestamp;

  CachedTile({required this.image, required this.timestamp});
}
```

### 3.5 바이너리 스트로크 저장 (Binary Stroke Format)

JSON 대신 바이너리 포맷으로 스트로크를 저장하여 성능을 최적화합니다.

```dart
// data/datasources/local/binary_stroke_storage.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

/// 바이너리 스트로크 파일 구조:
/// ┌─────────────────────────────────┐
/// │ Header (16 bytes)               │
/// │ - Magic: "WINK" (4 bytes)       │
/// │ - Version: uint16 (2 bytes)     │
/// │ - StrokeCount: uint32 (4 bytes) │
/// │ - Flags: uint16 (2 bytes)       │
/// │ - Reserved: 4 bytes             │
/// ├─────────────────────────────────┤
/// │ Stroke Index Table              │
/// │ - StrokeOffset[]: uint32        │
/// │ - StrokeSize[]: uint32          │
/// ├─────────────────────────────────┤
/// │ Stroke Data[]                   │
/// │ - StrokeHeader                  │
/// │ - BoundingBox                   │
/// │ - Points[]                      │
/// ├─────────────────────────────────┤
/// │ Spatial Index (QuadTree)        │
/// │ - 직렬화된 공간 인덱스           │
/// └─────────────────────────────────┘

class BinaryStrokeStorage {
  static const String magic = 'WINK';
  static const int version = 1;
  static const int headerSize = 16;

  /// 스트로크 리스트를 바이너리 파일로 저장
  Future<void> saveStrokes(String pageId, List<Stroke> strokes, String basePath) async {
    final filePath = p.join(basePath, '$pageId.strokes.bin');
    final file = File(filePath);

    final builder = BytesBuilder();

    // 1. Header 작성
    builder.add(magic.codeUnits); // 4 bytes
    builder.add(_uint16ToBytes(version)); // 2 bytes
    builder.add(_uint32ToBytes(strokes.length)); // 4 bytes
    builder.add(_uint16ToBytes(0)); // flags (2 bytes)
    builder.add(List.filled(4, 0)); // reserved (4 bytes)

    // 2. Stroke Index Table (나중에 오프셋 채움)
    final indexTableOffset = builder.length;
    final strokeOffsets = <int>[];
    final strokeSizes = <int>[];

    // 임시 공간 확보 (스트로크 수 * 8 bytes)
    builder.add(List.filled(strokes.length * 8, 0));

    // 3. Stroke Data 작성
    final dataStartOffset = builder.length;
    for (final stroke in strokes) {
      strokeOffsets.add(builder.length - dataStartOffset);
      final strokeData = _serializeStroke(stroke);
      builder.add(strokeData);
      strokeSizes.add(strokeData.length);
    }

    // 4. Index Table 업데이트
    final bytes = builder.toBytes();
    final byteData = ByteData.view(Uint8List.fromList(bytes).buffer);

    for (int i = 0; i < strokes.length; i++) {
      byteData.setUint32(indexTableOffset + i * 8, strokeOffsets[i], Endian.little);
      byteData.setUint32(indexTableOffset + i * 8 + 4, strokeSizes[i], Endian.little);
    }

    // 5. 파일 저장
    await file.writeAsBytes(byteData.buffer.asUint8List());
  }

  /// 바이너리 파일에서 스트로크 로드
  Future<List<Stroke>> loadStrokes(String pageId, String basePath) async {
    final filePath = p.join(basePath, '$pageId.strokes.bin');
    final file = File(filePath);

    if (!await file.exists()) return [];

    final bytes = await file.readAsBytes();
    final byteData = ByteData.view(bytes.buffer);

    // 1. Header 검증
    final fileMagic = String.fromCharCodes(bytes.sublist(0, 4));
    if (fileMagic != magic) {
      throw FormatException('Invalid stroke file: wrong magic number');
    }

    final fileVersion = byteData.getUint16(4, Endian.little);
    if (fileVersion > version) {
      throw FormatException('Unsupported stroke file version: $fileVersion');
    }

    final strokeCount = byteData.getUint32(6, Endian.little);

    // 2. Index Table 읽기
    final strokes = <Stroke>[];
    final indexTableOffset = headerSize;
    final dataStartOffset = indexTableOffset + strokeCount * 8;

    for (int i = 0; i < strokeCount; i++) {
      final offset = byteData.getUint32(indexTableOffset + i * 8, Endian.little);
      final size = byteData.getUint32(indexTableOffset + i * 8 + 4, Endian.little);

      final strokeBytes = bytes.sublist(
        dataStartOffset + offset,
        dataStartOffset + offset + size,
      );
      strokes.add(_deserializeStroke(strokeBytes));
    }

    return strokes;
  }

  /// 개별 스트로크 직렬화
  Uint8List _serializeStroke(Stroke stroke) {
    final builder = BytesBuilder();

    // StrokeHeader (32 bytes)
    builder.add(_stringToFixedBytes(stroke.id, 16)); // id
    builder.add([stroke.toolType.index]); // toolType (1 byte)
    builder.add(_colorToBytes(stroke.color)); // color (4 bytes)
    builder.add(_float32ToBytes(stroke.width)); // width (4 bytes)
    builder.add(_int64ToBytes(stroke.timestamp)); // timestamp (8 bytes)

    // BoundingBox (16 bytes)
    builder.add(_float32ToBytes(stroke.boundingBox.minX));
    builder.add(_float32ToBytes(stroke.boundingBox.minY));
    builder.add(_float32ToBytes(stroke.boundingBox.maxX));
    builder.add(_float32ToBytes(stroke.boundingBox.maxY));

    // Points (20 bytes per point)
    builder.add(_uint32ToBytes(stroke.points.length));
    for (final point in stroke.points) {
      builder.add(_float32ToBytes(point.x)); // 4 bytes
      builder.add(_float32ToBytes(point.y)); // 4 bytes
      builder.add(_float32ToBytes(point.pressure)); // 4 bytes
      builder.add(_float32ToBytes(point.tilt)); // 4 bytes
      builder.add(_int32ToBytes(point.timestamp)); // 4 bytes
    }

    return builder.toBytes();
  }

  /// 바이너리에서 스트로크 역직렬화
  Stroke _deserializeStroke(Uint8List bytes) {
    final byteData = ByteData.view(bytes.buffer);
    int offset = 0;

    // StrokeHeader
    final id = _fixedBytesToString(bytes.sublist(offset, offset + 16));
    offset += 16;
    final toolType = ToolType.values[bytes[offset]];
    offset += 1;
    final color = _bytesToColor(bytes.sublist(offset, offset + 4));
    offset += 4;
    final width = byteData.getFloat32(offset, Endian.little);
    offset += 4;
    final timestamp = byteData.getInt64(offset, Endian.little);
    offset += 8;

    // BoundingBox
    final minX = byteData.getFloat32(offset, Endian.little);
    offset += 4;
    final minY = byteData.getFloat32(offset, Endian.little);
    offset += 4;
    final maxX = byteData.getFloat32(offset, Endian.little);
    offset += 4;
    final maxY = byteData.getFloat32(offset, Endian.little);
    offset += 4;

    // Points
    final pointCount = byteData.getUint32(offset, Endian.little);
    offset += 4;

    final points = <StrokePoint>[];
    for (int i = 0; i < pointCount; i++) {
      points.add(StrokePoint(
        x: byteData.getFloat32(offset, Endian.little),
        y: byteData.getFloat32(offset + 4, Endian.little),
        pressure: byteData.getFloat32(offset + 8, Endian.little),
        tilt: byteData.getFloat32(offset + 12, Endian.little),
        timestamp: byteData.getInt32(offset + 16, Endian.little),
      ));
      offset += 20;
    }

    return Stroke(
      id: id,
      toolType: toolType,
      color: color,
      width: width,
      points: points,
      boundingBox: BoundingBox(minX: minX, minY: minY, maxX: maxX, maxY: maxY),
      timestamp: timestamp,
    );
  }

  // 유틸리티 메서드들
  Uint8List _uint16ToBytes(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  Uint8List _uint32ToBytes(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  Uint8List _int32ToBytes(int value) {
    final data = ByteData(4)..setInt32(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  Uint8List _int64ToBytes(int value) {
    final data = ByteData(8)..setInt64(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  Uint8List _float32ToBytes(double value) {
    final data = ByteData(4)..setFloat32(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  Uint8List _colorToBytes(Color color) {
    return Uint8List.fromList([color.red, color.green, color.blue, color.alpha]);
  }

  Color _bytesToColor(List<int> bytes) {
    return Color.fromARGB(bytes[3], bytes[0], bytes[1], bytes[2]);
  }

  Uint8List _stringToFixedBytes(String str, int length) {
    final bytes = str.codeUnits;
    final result = Uint8List(length);
    for (int i = 0; i < bytes.length && i < length; i++) {
      result[i] = bytes[i];
    }
    return result;
  }

  String _fixedBytesToString(List<int> bytes) {
    final endIndex = bytes.indexOf(0);
    return String.fromCharCodes(
      endIndex >= 0 ? bytes.sublist(0, endIndex) : bytes,
    );
  }
}
```

### 3.6 캔버스 위젯 (CanvasWidget)

```dart
// presentation/pages/editor/widgets/canvas_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../../../domain/entities/stroke.dart';
import '../../../../domain/services/stroke_engine.dart';

class CanvasWidget extends StatefulWidget {
  final StrokeEngine strokeEngine;
  final List<Stroke> strokes;
  final String templateType; // blank, lined, grid, dotted
  final Function(Stroke) onStrokeComplete;

  const CanvasWidget({
    super.key,
    required this.strokeEngine,
    required this.strokes,
    required this.templateType,
    required this.onStrokeComplete,
  });

  @override
  State<CanvasWidget> createState() => _CanvasWidgetState();
}

class _CanvasWidgetState extends State<CanvasWidget> {
  // 현재 그리는 중인 포인트들
  final List<Offset> _currentPoints = [];

  // 변환 (줌/팬)
  final TransformationController _transformController = TransformationController();

  // 손바닥 거부를 위한 상태
  bool _isPenInput = false;
  int? _activePenPointer;

  @override
  Widget build(BuildContext context) {
    return Listener(
      // 포인터 이벤트로 펜/터치 구분
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: InteractiveViewer(
        transformationController: _transformController,
        // 펜 입력 중에는 줌/팬 비활성화
        panEnabled: !_isPenInput,
        scaleEnabled: !_isPenInput,
        minScale: 0.5,
        maxScale: 5.0,
        child: CustomPaint(
          painter: CanvasPainter(
            strokes: widget.strokes,
            currentPoints: _currentPoints,
            currentColor: widget.strokeEngine.currentColor,
            currentWidth: widget.strokeEngine.currentWidth,
            templateType: widget.templateType,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    // 스타일러스 펜인지 확인
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      _isPenInput = true;
      _activePenPointer = event.pointer;

      // 변환 행렬 적용하여 실제 캔버스 좌표 계산
      final localPosition = _transformController.toScene(event.localPosition);

      widget.strokeEngine.startStroke(
        localPosition,
        event.pressure,
        event.tilt,
      );

      setState(() {
        _currentPoints.add(localPosition);
      });
    }
    // 터치인 경우 손바닥 거부 (펜 입력 중이면 무시)
    else if (event.kind == PointerDeviceKind.touch && !_isPenInput) {
      // 터치는 줌/팬에 사용 (InteractiveViewer가 처리)
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_activePenPointer == event.pointer) {
      final localPosition = _transformController.toScene(event.localPosition);

      widget.strokeEngine.continueStroke(
        localPosition,
        event.pressure,
        event.tilt,
      );

      setState(() {
        _currentPoints.add(localPosition);
      });
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_activePenPointer == event.pointer) {
      final stroke = widget.strokeEngine.endStroke();

      if (stroke != null) {
        widget.onStrokeComplete(stroke);
      }

      setState(() {
        _currentPoints.clear();
        _isPenInput = false;
        _activePenPointer = null;
      });
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_activePenPointer == event.pointer) {
      setState(() {
        _currentPoints.clear();
        _isPenInput = false;
        _activePenPointer = null;
      });
    }
  }
}

// 캔버스 페인터
class CanvasPainter extends CustomPainter {
  final List<Stroke> strokes;
  final List<Offset> currentPoints;
  final Color currentColor;
  final double currentWidth;
  final String templateType;

  CanvasPainter({
    required this.strokes,
    required this.currentPoints,
    required this.currentColor,
    required this.currentWidth,
    required this.templateType,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 배경 템플릿 그리기
    _drawTemplate(canvas, size);

    // 2. 저장된 스트로크 그리기
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }

    // 3. 현재 그리는 중인 스트로크 그리기
    if (currentPoints.isNotEmpty) {
      _drawCurrentStroke(canvas);
    }
  }

  void _drawTemplate(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE0E0E0)
      ..strokeWidth = 0.5;

    switch (templateType) {
      case 'lined':
        // 줄노트
        const lineSpacing = 30.0;
        for (double y = lineSpacing; y < size.height; y += lineSpacing) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        break;
      case 'grid':
        // 모눈
        const gridSize = 20.0;
        for (double x = 0; x < size.width; x += gridSize) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        for (double y = 0; y < size.height; y += gridSize) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        break;
      case 'dotted':
        // 도트
        const dotSpacing = 20.0;
        for (double x = dotSpacing; x < size.width; x += dotSpacing) {
          for (double y = dotSpacing; y < size.height; y += dotSpacing) {
            canvas.drawCircle(Offset(x, y), 1.5, paint);
          }
        }
        break;
      case 'blank':
      default:
        // 빈 페이지
        break;
    }
  }

  void _drawStroke(Canvas canvas, Stroke stroke) {
    if (stroke.points.length < 2) return;

    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // 형광펜은 반투명
    if (stroke.toolType == ToolType.highlighter) {
      paint.color = stroke.color.withOpacity(0.3);
      paint.strokeWidth = stroke.width * 3;
    }

    final path = Path();
    path.moveTo(stroke.points.first.x, stroke.points.first.y);

    for (int i = 1; i < stroke.points.length; i++) {
      final point = stroke.points[i];

      // 압력에 따른 굵기 변화 (선택적)
      if (stroke.toolType == ToolType.pen) {
        paint.strokeWidth = stroke.width * point.pressure;
      }

      path.lineTo(point.x, point.y);
    }

    canvas.drawPath(path, paint);
  }

  void _drawCurrentStroke(Canvas canvas) {
    if (currentPoints.length < 2) return;

    final paint = Paint()
      ..color = currentColor
      ..strokeWidth = currentWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(currentPoints.first.dx, currentPoints.first.dy);

    for (int i = 1; i < currentPoints.length; i++) {
      path.lineTo(currentPoints[i].dx, currentPoints[i].dy);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CanvasPainter oldDelegate) {
    return strokes != oldDelegate.strokes ||
        currentPoints.length != oldDelegate.currentPoints.length;
  }
}
```

### 3.3 데이터베이스 스키마 (Drift)

```dart
// data/datasources/local/database/app_database.dart

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

part 'app_database.g.dart';

// 폴더 테이블
class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get parentFolderId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get color => text().withDefault(const Constant('#2196F3'))();
  IntColumn get order => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// 노트 테이블
class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get folderId => text()();
  TextColumn get title => text()();
  TextColumn get tags => text().withDefault(const Constant('[]'))(); // JSON 배열
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  TextColumn get thumbnailPath => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get lastOpenedAt => dateTime()();
  TextColumn get deviceLastEdited => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

// 페이지 테이블
class Pages extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text().references(Notes, #id)();
  IntColumn get order => integer()();
  TextColumn get templateType => text().withDefault(const Constant('blank'))();
  TextColumn get canvasType => text().withDefault(const Constant('infinite'))();
  RealColumn get width => real().withDefault(const Constant(0))();
  RealColumn get height => real().withDefault(const Constant(0))();
  TextColumn get backgroundColor => text().withDefault(const Constant('#FFFFFF'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// 첨부파일 테이블
class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text().references(Notes, #id)();
  TextColumn get type => text()(); // pdf, image
  TextColumn get fileName => text()();
  IntColumn get fileSize => integer()();
  TextColumn get storagePath => text()();
  TextColumn get checksum => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// 동기화 로그 (Phase 2)
class SyncLogs extends Table {
  TextColumn get id => text()();
  TextColumn get deviceId => text()();
  IntColumn get version => integer()();
  TextColumn get changeType => text()(); // create, update, delete
  TextColumn get entityType => text()(); // note, page, stroke, folder
  TextColumn get entityId => text()();
  TextColumn get changeData => text()(); // JSON
  BoolColumn get conflictFlag => boolean().withDefault(const Constant(false))();
  DateTimeColumn get timestamp => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Folders, Notes, Pages, Attachments, SyncLogs])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // 마이그레이션
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();

      // 기본 워크스페이스 생성
      await into(folders).insert(FoldersCompanion.insert(
        id: 'default_personal',
        workspaceId: 'personal',
        name: '개인',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // 버전별 마이그레이션
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'winote.sqlite'));
    return NativeDatabase(file);
  });
}
```

---

## 4. 상태 관리 (Riverpod)

### 4.1 Provider 구조

```dart
// presentation/providers/note_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/note.dart';
import '../../domain/repositories/note_repository.dart';

// 레포지토리 Provider
final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  // 실제 구현체 주입
  return NoteRepositoryImpl(ref.watch(databaseProvider));
});

// 노트 목록 상태
final noteListProvider = StateNotifierProvider<NoteListNotifier, AsyncValue<List<Note>>>((ref) {
  return NoteListNotifier(ref.watch(noteRepositoryProvider));
});

class NoteListNotifier extends StateNotifier<AsyncValue<List<Note>>> {
  final NoteRepository _repository;

  NoteListNotifier(this._repository) : super(const AsyncValue.loading()) {
    loadNotes();
  }

  Future<void> loadNotes() async {
    state = const AsyncValue.loading();
    try {
      final notes = await _repository.getAllNotes();
      state = AsyncValue.data(notes);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> createNote(String title, String folderId) async {
    try {
      final note = await _repository.createNote(title, folderId);
      state = AsyncValue.data([...state.value ?? [], note]);
    } catch (e) {
      // 에러 처리
    }
  }

  Future<void> deleteNote(String noteId) async {
    try {
      await _repository.deleteNote(noteId);
      state = AsyncValue.data(
        (state.value ?? []).where((n) => n.id != noteId).toList(),
      );
    } catch (e) {
      // 에러 처리
    }
  }
}

// 현재 선택된 노트
final selectedNoteProvider = StateProvider<Note?>((ref) => null);

// 즐겨찾기 노트
final favoriteNotesProvider = Provider<List<Note>>((ref) {
  final notes = ref.watch(noteListProvider);
  return notes.maybeWhen(
    data: (list) => list.where((n) => n.isFavorite).toList(),
    orElse: () => [],
  );
});

// 최근 노트 (최대 10개)
final recentNotesProvider = Provider<List<Note>>((ref) {
  final notes = ref.watch(noteListProvider);
  return notes.maybeWhen(
    data: (list) {
      final sorted = [...list]..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
      return sorted.take(10).toList();
    },
    orElse: () => [],
  );
});
```

### 4.2 에디터 상태

```dart
// presentation/providers/editor_provider.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/stroke.dart';
import '../../domain/entities/page.dart';
import '../../domain/services/stroke_engine.dart';

// 스트로크 엔진 Provider
final strokeEngineProvider = Provider<StrokeEngine>((ref) {
  return StrokeEngine();
});

// 에디터 상태
class EditorState {
  final String noteId;
  final List<Page> pages;
  final int currentPageIndex;
  final Map<String, List<Stroke>> strokesByPage; // pageId -> strokes
  final ToolType selectedTool;
  final Color selectedColor;
  final double strokeWidth;
  final bool isModified;

  const EditorState({
    required this.noteId,
    this.pages = const [],
    this.currentPageIndex = 0,
    this.strokesByPage = const {},
    this.selectedTool = ToolType.pen,
    this.selectedColor = const Color(0xFF000000),
    this.strokeWidth = 2.0,
    this.isModified = false,
  });

  EditorState copyWith({
    String? noteId,
    List<Page>? pages,
    int? currentPageIndex,
    Map<String, List<Stroke>>? strokesByPage,
    ToolType? selectedTool,
    Color? selectedColor,
    double? strokeWidth,
    bool? isModified,
  }) {
    return EditorState(
      noteId: noteId ?? this.noteId,
      pages: pages ?? this.pages,
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
      strokesByPage: strokesByPage ?? this.strokesByPage,
      selectedTool: selectedTool ?? this.selectedTool,
      selectedColor: selectedColor ?? this.selectedColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      isModified: isModified ?? this.isModified,
    );
  }

  Page? get currentPage =>
    currentPageIndex < pages.length ? pages[currentPageIndex] : null;

  List<Stroke> get currentStrokes =>
    strokesByPage[currentPage?.id] ?? [];
}

final editorProvider = StateNotifierProvider<EditorNotifier, EditorState?>((ref) {
  return EditorNotifier(ref);
});

class EditorNotifier extends StateNotifier<EditorState?> {
  final Ref _ref;

  EditorNotifier(this._ref) : super(null);

  Future<void> loadNote(String noteId) async {
    // 노트 및 페이지 로드
    final repository = _ref.read(noteRepositoryProvider);
    final note = await repository.getNote(noteId);
    final pages = await repository.getPages(noteId);
    final strokesByPage = <String, List<Stroke>>{};

    for (final page in pages) {
      strokesByPage[page.id] = await repository.getStrokes(page.id);
    }

    state = EditorState(
      noteId: noteId,
      pages: pages,
      strokesByPage: strokesByPage,
    );
  }

  void selectTool(ToolType tool) {
    if (state == null) return;
    state = state!.copyWith(selectedTool: tool);
    _ref.read(strokeEngineProvider).currentTool = tool;
  }

  void selectColor(Color color) {
    if (state == null) return;
    state = state!.copyWith(selectedColor: color);
    _ref.read(strokeEngineProvider).currentColor = color;
  }

  void setStrokeWidth(double width) {
    if (state == null) return;
    state = state!.copyWith(strokeWidth: width);
    _ref.read(strokeEngineProvider).currentWidth = width;
  }

  void addStroke(Stroke stroke) {
    if (state == null || state!.currentPage == null) return;

    final pageId = state!.currentPage!.id;
    final currentStrokes = List<Stroke>.from(state!.strokesByPage[pageId] ?? []);
    currentStrokes.add(stroke);

    final newStrokesByPage = Map<String, List<Stroke>>.from(state!.strokesByPage);
    newStrokesByPage[pageId] = currentStrokes;

    state = state!.copyWith(
      strokesByPage: newStrokesByPage,
      isModified: true,
    );

    // 자동 저장 트리거 (debounce)
    _scheduleAutoSave();
  }

  void undo() {
    final stroke = _ref.read(strokeEngineProvider).undo();
    if (stroke != null && state != null && state!.currentPage != null) {
      final pageId = state!.currentPage!.id;
      final currentStrokes = List<Stroke>.from(state!.strokesByPage[pageId] ?? []);
      currentStrokes.remove(stroke);

      final newStrokesByPage = Map<String, List<Stroke>>.from(state!.strokesByPage);
      newStrokesByPage[pageId] = currentStrokes;

      state = state!.copyWith(
        strokesByPage: newStrokesByPage,
        isModified: true,
      );
    }
  }

  void redo() {
    final stroke = _ref.read(strokeEngineProvider).redo();
    if (stroke != null && state != null && state!.currentPage != null) {
      final pageId = state!.currentPage!.id;
      final currentStrokes = List<Stroke>.from(state!.strokesByPage[pageId] ?? []);
      currentStrokes.add(stroke);

      final newStrokesByPage = Map<String, List<Stroke>>.from(state!.strokesByPage);
      newStrokesByPage[pageId] = currentStrokes;

      state = state!.copyWith(
        strokesByPage: newStrokesByPage,
        isModified: true,
      );
    }
  }

  void goToPage(int index) {
    if (state == null || index < 0 || index >= state!.pages.length) return;
    state = state!.copyWith(currentPageIndex: index);
  }

  Future<void> addPage(String templateType) async {
    if (state == null) return;

    final repository = _ref.read(noteRepositoryProvider);
    final newPage = await repository.createPage(
      state!.noteId,
      state!.pages.length,
      templateType,
    );

    state = state!.copyWith(
      pages: [...state!.pages, newPage],
      currentPageIndex: state!.pages.length,
      isModified: true,
    );
  }

  Future<void> save() async {
    if (state == null || !state!.isModified) return;

    final repository = _ref.read(noteRepositoryProvider);

    // 각 페이지의 스트로크 저장
    for (final entry in state!.strokesByPage.entries) {
      await repository.saveStrokes(entry.key, entry.value);
    }

    // 노트 업데이트 시간 갱신
    await repository.updateNote(state!.noteId);

    state = state!.copyWith(isModified: false);
  }

  void _scheduleAutoSave() {
    // 3초 후 자동 저장 (debounce 적용)
    Future.delayed(const Duration(seconds: 3), () {
      if (state?.isModified == true) {
        save();
      }
    });
  }
}
```

---

## 5. 플랫폼 채널

### 5.1 Android S Pen 연동

```kotlin
// android/app/src/main/kotlin/com/winote/StylusPlugin.kt

package com.winote

import android.view.MotionEvent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class StylusPlugin(flutterEngine: FlutterEngine) {
    private val channel = MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "com.winote/stylus"
    )

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getSPenSdkVersion" -> {
                    // Samsung S Pen SDK 버전 확인
                    result.success(getSPenVersion())
                }
                "enableSPenHover" -> {
                    // S Pen 호버 이벤트 활성화
                    enableHover()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getSPenVersion(): String {
        // Samsung S Pen SDK 버전 반환
        return "1.0"
    }

    private fun enableHover() {
        // S Pen 호버 이벤트 리스너 설정
    }

    // MotionEvent에서 S Pen 데이터 추출
    fun extractSPenData(event: MotionEvent): Map<String, Any> {
        return mapOf(
            "x" to event.x,
            "y" to event.y,
            "pressure" to event.pressure,
            "tiltX" to event.getAxisValue(MotionEvent.AXIS_TILT),
            "toolType" to when (event.getToolType(0)) {
                MotionEvent.TOOL_TYPE_STYLUS -> "stylus"
                MotionEvent.TOOL_TYPE_ERASER -> "eraser"
                else -> "unknown"
            },
            "buttonState" to event.buttonState
        )
    }
}
```

### 5.2 Windows Ink 연동

```cpp
// windows/winote_plugin/windows_ink_plugin.cpp

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <windows.h>
#include <winuser.h>

namespace {

class WindowsInkPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  WindowsInkPlugin(flutter::PluginRegistrarWindows* registrar);
  virtual ~WindowsInkPlugin();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Windows Ink 초기화
  bool InitializeWindowsInk();

  // 펜 입력 처리
  void ProcessPenInput(POINTER_INFO* pointerInfo);
};

void WindowsInkPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

  if (method_call.method_name().compare("initializeInk") == 0) {
    bool success = InitializeWindowsInk();
    result->Success(flutter::EncodableValue(success));
  } else if (method_call.method_name().compare("getPenCapabilities") == 0) {
    // 펜 기능 확인 (압력, 기울기 지원 여부)
    flutter::EncodableMap capabilities;
    capabilities[flutter::EncodableValue("pressure")] = flutter::EncodableValue(true);
    capabilities[flutter::EncodableValue("tilt")] = flutter::EncodableValue(true);
    capabilities[flutter::EncodableValue("eraser")] = flutter::EncodableValue(true);
    result->Success(flutter::EncodableValue(capabilities));
  } else {
    result->NotImplemented();
  }
}

bool WindowsInkPlugin::InitializeWindowsInk() {
  // Windows Ink 워크스페이스 초기화
  // 펜 입력 리스너 등록
  return true;
}

}  // namespace

void WindowsInkPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  WindowsInkPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
```

---

## 6. 폴더 기반 동기화 (MVP)

OneDrive/Google Drive 폴더를 통한 Obsidian 스타일 동기화입니다.

### 6.1 동기화 아키텍처

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Folder-Based Sync Architecture                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Windows (Galaxy Book)              Android (Galaxy Tab)            │
│  ┌─────────────────────┐            ┌─────────────────────┐        │
│  │   Winote App        │            │   Winote App        │        │
│  │   └─ Local DB       │            │   └─ Local DB       │        │
│  └──────────┬──────────┘            └──────────┬──────────┘        │
│             │                                   │                   │
│             ▼                                   ▼                   │
│  ┌─────────────────────┐            ┌─────────────────────┐        │
│  │   Sync Folder       │◀──────────▶│   Sync Folder       │        │
│  │   (C:\Users\...\    │   Cloud    │   (/storage/.../    │        │
│  │    OneDrive\Winote) │   Sync     │    OneDrive/Winote) │        │
│  └─────────────────────┘            └─────────────────────┘        │
│             │                                   │                   │
│             └───────────────┬───────────────────┘                   │
│                             ▼                                       │
│                  ┌─────────────────────┐                           │
│                  │   Cloud Storage     │                           │
│                  │   (OneDrive/        │                           │
│                  │    Google Drive)    │                           │
│                  └─────────────────────┘                           │
└─────────────────────────────────────────────────────────────────────┘
```

### 6.2 동기화 폴더 구조

```
Winote/                          # 동기화 루트 폴더
├── .winote/                     # 메타데이터 폴더 (숨김)
│   ├── device_id.txt            # 기기 식별자
│   ├── sync_state.json          # 마지막 동기화 상태
│   └── conflict_log.json        # 충돌 기록
│
├── notebooks/                   # 노트북 폴더
│   ├── 수학 강의/               # 노트북 1
│   │   ├── notebook.json        # 노트북 메타데이터
│   │   ├── 1장 - 미분/          # 노트 1
│   │   │   ├── note.json        # 노트 메타데이터
│   │   │   ├── page_001.strokes.bin  # 페이지 1 스트로크
│   │   │   ├── page_002.strokes.bin  # 페이지 2 스트로크
│   │   │   └── thumb.png        # 썸네일
│   │   └── 2장 - 적분/          # 노트 2
│   │       └── ...
│   └── 영어 회화/               # 노트북 2
│       └── ...
│
└── attachments/                 # 첨부파일 폴더
    ├── pdf/                     # PDF 원본
    │   └── {uuid}.pdf
    └── images/                  # 이미지
        └── {uuid}.png
```

### 6.3 충돌 해결 전략

```dart
// domain/services/sync_service.dart

enum ConflictResolution {
  keepLocal,    // 로컬 버전 유지
  keepRemote,   // 원격 버전 유지
  keepBoth,     // 둘 다 유지 (복사본 생성)
  merge,        // 병합 시도 (스트로크 레벨)
}

class SyncService {
  final FileSystemWatcher _watcher;
  final ConflictResolver _conflictResolver;

  /// 파일 변경 감지 및 동기화
  void startWatching(String syncFolderPath) {
    _watcher.watch(syncFolderPath, (event) async {
      switch (event.type) {
        case FileEventType.created:
        case FileEventType.modified:
          await _handleFileChange(event.path);
          break;
        case FileEventType.deleted:
          await _handleFileDeletion(event.path);
          break;
      }
    });
  }

  /// 충돌 감지 및 해결
  Future<void> _handleFileChange(String path) async {
    final localVersion = await _getLocalVersion(path);
    final remoteVersion = await _getRemoteVersion(path);

    if (localVersion == null) {
      // 새 파일: 로컬에 추가
      await _importFromSync(path);
      return;
    }

    if (remoteVersion.timestamp > localVersion.timestamp) {
      // 원격이 최신: 로컬 업데이트
      await _importFromSync(path);
    } else if (localVersion.timestamp > remoteVersion.timestamp) {
      // 로컬이 최신: 이미 동기화됨
      return;
    } else {
      // 동시 편집: 충돌 발생
      await _resolveConflict(path, localVersion, remoteVersion);
    }
  }

  /// 충돌 해결
  Future<void> _resolveConflict(
    String path,
    NoteVersion local,
    NoteVersion remote,
  ) async {
    // 기본: 마지막 편집 기기 우선
    // 사용자가 설정에서 변경 가능
    final resolution = await _conflictResolver.resolve(local, remote);

    switch (resolution) {
      case ConflictResolution.keepLocal:
        await _exportToSync(path); // 로컬로 덮어쓰기
        break;
      case ConflictResolution.keepRemote:
        await _importFromSync(path); // 원격으로 덮어쓰기
        break;
      case ConflictResolution.keepBoth:
        await _createConflictCopy(path, local, remote);
        break;
      case ConflictResolution.merge:
        await _mergeStrokes(path, local, remote);
        break;
    }

    // 충돌 로그 기록
    await _logConflict(path, resolution);
  }

  /// 스트로크 레벨 병합
  Future<void> _mergeStrokes(
    String path,
    NoteVersion local,
    NoteVersion remote,
  ) async {
    // 스트로크 ID 기반 병합
    final localStrokes = await _loadStrokes(local.path);
    final remoteStrokes = await _loadStrokes(remote.path);

    final mergedStrokes = <Stroke>[];
    final seenIds = <String>{};

    // 타임스탬프 기준 정렬 후 병합
    final allStrokes = [...localStrokes, ...remoteStrokes]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    for (final stroke in allStrokes) {
      if (!seenIds.contains(stroke.id)) {
        mergedStrokes.add(stroke);
        seenIds.add(stroke.id);
      }
    }

    await _saveStrokes(path, mergedStrokes);
  }
}
```

---

## 7. 성능 최적화

### 7.1 렌더링 최적화 (3-Layer Architecture)

```dart
// 1. 레이어 분리: 배경/스트로크/현재 그리기를 별도 레이어로
class OptimizedCanvasWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 레이어 1: 배경 템플릿 (정적, 변경 안함)
        RepaintBoundary(
          child: CustomPaint(
            painter: TemplatePainter(templateType: 'grid'),
          ),
        ),
        // 레이어 2: 완료된 스트로크 (타일 캐시)
        RepaintBoundary(
          child: TiledStrokesWidget(
            tileCache: tileCache,
            strokes: committedStrokes,
            viewport: viewport,
          ),
        ),
        // 레이어 3: 현재 그리기 (벡터 실시간)
        CustomPaint(
          painter: ActiveStrokePainter(
            currentPoints: currentPoints,
            color: currentColor,
            width: currentWidth,
          ),
        ),
      ],
    );
  }
}

// 2. 타일 기반 래스터 렌더링
class TiledStrokesWidget extends StatelessWidget {
  final TileCache tileCache;
  final List<Stroke> strokes;
  final Rect viewport;

  @override
  Widget build(BuildContext context) {
    // 뷰포트에 해당하는 타일만 렌더링
    final visibleTiles = _calculateVisibleTiles(viewport);

    return CustomPaint(
      painter: TiledPainter(
        tileCache: tileCache,
        visibleTiles: visibleTiles,
        strokes: strokes,
      ),
    );
  }
}

// 3. 가변 굵기 메쉬 렌더링
class MeshStrokePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      final vertices = _generateMeshVertices(stroke);
      final paint = Paint()..color = stroke.color;

      // GPU 최적화: Triangle Strip으로 렌더링
      canvas.drawVertices(
        vertices,
        BlendMode.srcOver,
        paint,
      );
    }
  }

  Vertices _generateMeshVertices(Stroke stroke) {
    final positions = <Offset>[];
    final colors = <Color>[];

    for (int i = 0; i < stroke.points.length - 1; i++) {
      final p1 = stroke.points[i];
      final p2 = stroke.points[i + 1];

      // 압력에 따른 굵기 계산
      final width1 = stroke.width * p1.pressure;
      final width2 = stroke.width * p2.pressure;

      // 방향 벡터 계산
      final direction = Offset(p2.x - p1.x, p2.y - p1.y);
      final perpendicular = Offset(-direction.dy, direction.dx).normalized();

      // 사각형 (2개 삼각형) 정점 추가
      positions.addAll([
        Offset(p1.x + perpendicular.dx * width1, p1.y + perpendicular.dy * width1),
        Offset(p1.x - perpendicular.dx * width1, p1.y - perpendicular.dy * width1),
        Offset(p2.x + perpendicular.dx * width2, p2.y + perpendicular.dy * width2),
        Offset(p2.x - perpendicular.dx * width2, p2.y - perpendicular.dy * width2),
      ]);

      colors.addAll([stroke.color, stroke.color, stroke.color, stroke.color]);
    }

    return Vertices(
      VertexMode.triangleStrip,
      positions,
      colors: colors,
    );
  }
}
```

### 7.2 메모리 최적화

```dart
// 페이지 단위 LRU 캐시 + 바이너리 직접 로딩
class PageManager {
  final Map<String, PageCache> _loadedPages = {};
  final List<String> _lruOrder = [];
  final int maxLoadedPages = 5;
  final BinaryStrokeStorage _storage;

  PageManager(this._storage);

  Future<List<Stroke>> getPageStrokes(String pageId, String basePath) async {
    if (_loadedPages.containsKey(pageId)) {
      _updateLRU(pageId);
      return _loadedPages[pageId]!.strokes;
    }

    // 캐시가 가득 찼으면 가장 오래된 페이지 언로드
    while (_loadedPages.length >= maxLoadedPages) {
      _unloadOldestPage();
    }

    // 바이너리 파일에서 직접 로드
    final strokes = await _storage.loadStrokes(pageId, basePath);

    _loadedPages[pageId] = PageCache(
      strokes: strokes,
      loadedAt: DateTime.now(),
    );
    _lruOrder.add(pageId);

    return strokes;
  }

  void _updateLRU(String pageId) {
    _lruOrder.remove(pageId);
    _lruOrder.add(pageId);
  }

  void _unloadOldestPage() {
    if (_lruOrder.isNotEmpty) {
      final oldestId = _lruOrder.removeAt(0);
      _loadedPages.remove(oldestId);
    }
  }

  /// 메모리 사용량 계산
  int get estimatedMemoryUsage {
    int total = 0;
    for (final cache in _loadedPages.values) {
      for (final stroke in cache.strokes) {
        // 스트로크당 대략적 메모리: 헤더 + 포인트 * 20bytes
        total += 100 + stroke.points.length * 20;
      }
    }
    return total;
  }

  /// 메모리 압박 시 강제 언로드
  void handleMemoryPressure() {
    // 현재 페이지 제외하고 모두 언로드
    while (_loadedPages.length > 1) {
      _unloadOldestPage();
    }
  }
}

class PageCache {
  final List<Stroke> strokes;
  final DateTime loadedAt;

  PageCache({required this.strokes, required this.loadedAt});
}
```

### 7.3 성능 벤치마크 기준

| 시나리오 | 목표 | 측정 방법 |
|---------|------|---------|
| **빈 캔버스 첫 입력** | < 10ms | Stylus down → 첫 픽셀 |
| **1000 스트로크 렌더링** | 60fps | 평균 프레임 시간 |
| **페이지 로드 (500 스트로크)** | < 100ms | 파일 읽기 완료 |
| **페이지 저장 (500 스트로크)** | < 50ms | 파일 쓰기 완료 |
| **줌 변경 시 리렌더링** | < 16ms | 타일 캐시 재생성 |
| **메모리 사용량 (10페이지)** | < 100MB | 힙 메모리 |

### 7.4 디버그 오버레이 (개발용)

```dart
// presentation/widgets/debug_overlay.dart

class DebugOverlay extends StatelessWidget {
  final StrokeEngine engine;
  final TileCache tileCache;
  final PageManager pageManager;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 10,
      right: 10,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('FPS: ${_fps.toStringAsFixed(1)}', style: _style),
            Text('Strokes: ${engine.strokeCount}', style: _style),
            Text('Points: ${engine.totalPoints}', style: _style),
            Text('Tiles: ${tileCache.cachedTileCount}', style: _style),
            Text('Memory: ${(pageManager.estimatedMemoryUsage / 1024 / 1024).toStringAsFixed(1)} MB', style: _style),
          ],
        ),
      ),
    );
  }
}
```

---

## 8. 테스트 전략

### 7.1 테스트 레이어

```
tests/
├── unit/                          # 단위 테스트
│   ├── stroke_engine_test.dart
│   ├── note_service_test.dart
│   └── stroke_serialization_test.dart
├── widget/                        # 위젯 테스트
│   ├── canvas_widget_test.dart
│   ├── toolbar_test.dart
│   └── note_card_test.dart
├── integration/                   # 통합 테스트
│   ├── note_crud_test.dart
│   ├── stroke_save_load_test.dart
│   └── pdf_annotation_test.dart
└── performance/                   # 성능 테스트
    ├── render_benchmark_test.dart
    └── large_note_test.dart
```

### 7.2 핵심 테스트 케이스

```dart
// test/unit/stroke_engine_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:winote/domain/services/stroke_engine.dart';

void main() {
  group('StrokeEngine', () {
    late StrokeEngine engine;

    setUp(() {
      engine = StrokeEngine();
    });

    test('스트로크 시작/계속/종료가 올바르게 동작해야 함', () {
      engine.startStroke(const Offset(0, 0), 0.5, 0);
      engine.continueStroke(const Offset(10, 10), 0.6, 0);
      engine.continueStroke(const Offset(20, 20), 0.7, 0);

      final stroke = engine.endStroke();

      expect(stroke, isNotNull);
      expect(stroke!.points.length, equals(3));
      expect(stroke.points.first.x, equals(0));
      expect(stroke.points.last.x, equals(20));
    });

    test('실행취소가 마지막 스트로크를 제거해야 함', () {
      // 스트로크 2개 추가
      engine.startStroke(const Offset(0, 0), 0.5, 0);
      engine.endStroke();

      engine.startStroke(const Offset(100, 100), 0.5, 0);
      engine.endStroke();

      // 실행취소
      final undone = engine.undo();

      expect(undone, isNotNull);
      expect(undone!.points.first.x, equals(100));
    });

    test('재실행이 취소된 스트로크를 복원해야 함', () {
      engine.startStroke(const Offset(0, 0), 0.5, 0);
      engine.endStroke();

      engine.undo();
      final redone = engine.redo();

      expect(redone, isNotNull);
      expect(redone!.points.first.x, equals(0));
    });

    test('라쏘 선택이 영역 내 스트로크를 반환해야 함', () {
      // 스트로크 추가
      engine.startStroke(const Offset(50, 50), 0.5, 0);
      engine.continueStroke(const Offset(60, 60), 0.5, 0);
      engine.endStroke();

      // 선택 영역 정의
      final selectionPath = Path()
        ..addRect(const Rect.fromLTWH(40, 40, 30, 30));

      final selected = engine.selectStrokesInPath(selectionPath);

      expect(selected.length, equals(1));
    });
  });
}
```

---

## 9. 배포 설정

### 8.1 빌드 설정

```yaml
# pubspec.yaml

name: winote
description: 태블릿 필기 앱
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.2.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

  # 상태 관리
  flutter_riverpod: ^2.4.0

  # 라우팅
  go_router: ^12.0.0

  # 데이터베이스
  drift: ^2.14.0
  sqlite3_flutter_libs: ^0.5.0

  # 파일 처리
  path_provider: ^2.1.0
  path: ^1.8.0

  # PDF
  syncfusion_flutter_pdfviewer: ^23.2.0

  # 유틸리티
  uuid: ^4.2.0
  intl: ^0.18.0
  json_annotation: ^4.8.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
  build_runner: ^2.4.0
  drift_dev: ^2.14.0
  json_serializable: ^6.7.0
  mocktail: ^1.0.0

flutter:
  uses-material-design: true

  assets:
    - assets/templates/
    - assets/icons/
```

### 8.2 Android 설정

```kotlin
// android/app/build.gradle.kts

android {
    compileSdk = 34

    defaultConfig {
        applicationId = "com.winote.app"
        minSdk = 26  // Android 8.0+ (펜 API 지원)
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}
```

### 8.3 Windows 설정

```cmake
# windows/CMakeLists.txt

cmake_minimum_required(VERSION 3.14)
project(winote LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Windows Ink 라이브러리 링크
find_library(WINDOWS_INK_LIB InkObj)
target_link_libraries(${BINARY_NAME} PRIVATE ${WINDOWS_INK_LIB})
```

---

*이 문서는 개발 진행에 따라 업데이트됩니다.*
