import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:winote/core/services/note_storage_service.dart';
import 'package:winote/core/services/stroke_smoothing_service.dart';
import 'package:winote/core/services/shape_recognition_service.dart';
import 'package:winote/core/providers/drawing_state.dart';
import 'package:winote/domain/entities/stroke.dart';
import 'package:winote/domain/entities/stroke_point.dart';
import 'package:winote/domain/entities/bounding_box.dart';

/// Winote 앱 종합 테스트베드
/// 모든 서비스와 엔티티의 기능 및 연동을 테스트
void main() {
  late Directory tempDir;
  late String testBasePath;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('winote_comprehensive_test_');
    testBasePath = tempDir.path;
    print('테스트 디렉토리: $testBasePath');
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    print('테스트 디렉토리 정리 완료');
  });

  // ========================================
  // 1. Note/NotePage 엔티티 테스트
  // ========================================
  group('📝 Note/NotePage 엔티티 테스트', () {
    test('Note 생성 및 기본 속성', () {
      final note = Note(
        id: 'note-1',
        title: '테스트 노트',
        pages: [NotePage(pageNumber: 0, strokes: [])],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      expect(note.id, equals('note-1'));
      expect(note.title, equals('테스트 노트'));
      expect(note.pageCount, equals(1));
      expect(note.isFavorite, isFalse);
    });

    test('페이지 추가 (fromPageNumber 사용)', () {
      final note = Note(
        id: 'note-2',
        title: '페이지 추가 테스트',
        pages: [
          NotePage(
            pageNumber: 0,
            strokes: [],
            templateIndex: PageTemplate.lined.index,
          ),
        ],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      // 현재 페이지 템플릿을 복사하여 새 페이지 추가
      final updatedNote = note.addPage(fromPageNumber: 0);

      expect(updatedNote.pageCount, equals(2));
      expect(updatedNote.pages[1].templateIndex, equals(PageTemplate.lined.index));
    });

    test('페이지 삭제', () {
      var note = Note(
        id: 'note-3',
        title: '페이지 삭제 테스트',
        pages: [
          NotePage(pageNumber: 0, strokes: []),
          NotePage(pageNumber: 1, strokes: []),
          NotePage(pageNumber: 2, strokes: []),
        ],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      note = note.deletePage(1);

      expect(note.pageCount, equals(2));
      expect(note.pages[0].pageNumber, equals(0));
      expect(note.pages[1].pageNumber, equals(2)); // 원래 pageNumber 유지 (재인덱싱 없음)
    });

    test('페이지 복제', () {
      final stroke = _createTestStroke('s1', 10);
      var note = Note(
        id: 'note-4',
        title: '페이지 복제 테스트',
        pages: [
          NotePage(
            pageNumber: 0,
            strokes: [stroke],
            templateIndex: PageTemplate.grid.index,
          ),
        ],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      note = note.duplicatePage(0);

      expect(note.pageCount, equals(2));
      expect(note.pages[1].strokes.length, equals(1));
      expect(note.pages[1].templateIndex, equals(PageTemplate.grid.index));
      // 복제된 스트로크는 새로운 ID를 가져야 함
      expect(note.pages[1].strokes[0].id, isNot(equals(stroke.id)));
    });

    test('책갈피 토글', () {
      var note = Note(
        id: 'note-5',
        title: '책갈피 테스트',
        pages: [
          NotePage(pageNumber: 0, strokes: []),
          NotePage(pageNumber: 1, strokes: []),
        ],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      note = note.togglePageBookmark(0);
      expect(note.isPageBookmarked(0), isTrue);
      expect(note.bookmarkedPages.length, equals(1));

      note = note.togglePageBookmark(0);
      expect(note.isPageBookmarked(0), isFalse);
      expect(note.bookmarkedPages.length, equals(0));
    });

    test('페이지 순서 변경', () {
      var note = Note(
        id: 'note-6',
        title: '순서 변경 테스트',
        pages: [
          NotePage(pageNumber: 0, strokes: [_createTestStroke('p0', 5)]),
          NotePage(pageNumber: 1, strokes: [_createTestStroke('p1', 5)]),
          NotePage(pageNumber: 2, strokes: [_createTestStroke('p2', 5)]),
        ],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      // 첫 번째 페이지를 마지막으로 이동
      note = note.reorderPages(0, 2);

      expect(note.pageCount, equals(3));
      // 페이지 번호는 재정렬되어야 함
      for (int i = 0; i < 3; i++) {
        expect(note.pages[i].pageNumber, equals(i));
      }
    });

    test('즐겨찾기 및 태그', () {
      var note = Note(
        id: 'note-7',
        title: '메타데이터 테스트',
        pages: [NotePage(pageNumber: 0, strokes: [])],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      note = note.copyWith(
        isFavorite: true,
        tags: ['flutter', 'dart', '테스트'],
      );

      expect(note.isFavorite, isTrue);
      expect(note.tags.length, equals(3));
      expect(note.tags, containsAll(['flutter', 'dart', '테스트']));
    });

    test('폴더 할당', () {
      var note = Note(
        id: 'note-8',
        title: '폴더 테스트',
        pages: [NotePage(pageNumber: 0, strokes: [])],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      note = note.copyWith(folderId: 'folder-1');
      expect(note.folderId, equals('folder-1'));

      note = note.copyWith(clearFolder: true);
      expect(note.folderId, isNull);
    });
  });

  // ========================================
  // 2. Stroke/StrokePoint 엔티티 테스트
  // ========================================
  group('✏️ Stroke/StrokePoint 테스트', () {
    test('Stroke 생성 및 포인트 추가', () {
      final stroke = Stroke(
        id: 'stroke-1',
        toolType: ToolType.pen,
        color: Colors.black,
        width: 2.0,
        points: [],
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      // addPoint는 void 반환하고 직접 수정함
      stroke.addPoint(const StrokePoint(
        x: 10,
        y: 20,
        pressure: 0.5,
        tilt: 0.1,
        timestamp: 1000,
      ),);

      expect(stroke.points.length, equals(1));
      expect(stroke.points[0].x, equals(10));
    });

    test('필압 기반 굵기 계산', () {
      final stroke = _createTestStroke('pressure-test', 5);

      // 낮은 필압 (0.3)
      final lowWidth = stroke.getWidthAtPressure(0.3, 0.6);
      // 높은 필압 (0.8)
      final highWidth = stroke.getWidthAtPressure(0.8, 0.6);

      expect(highWidth, greaterThan(lowWidth));
      print('낮은 필압 굵기: $lowWidth, 높은 필압 굵기: $highWidth');
    });

    test('BoundingBox 계산', () {
      final points = <StrokePoint>[
        const StrokePoint(x: 10, y: 20, pressure: 0.5, tilt: 0, timestamp: 0),
        const StrokePoint(x: 100, y: 50, pressure: 0.5, tilt: 0, timestamp: 16),
        const StrokePoint(x: 50, y: 150, pressure: 0.5, tilt: 0, timestamp: 32),
      ];

      final stroke = Stroke(
        id: 'bbox-test',
        toolType: ToolType.pen,
        color: Colors.black,
        width: 2.0,
        points: points,
        timestamp: 0,
      );

      final bbox = stroke.boundingBox;
      expect(bbox.minX, equals(10));
      expect(bbox.maxX, equals(100));
      expect(bbox.minY, equals(20));
      expect(bbox.maxY, equals(150));
    });

    test('BoundingBox 겹침 확인', () {
      final bbox = BoundingBox(minX: 0, minY: 0, maxX: 100, maxY: 100);

      expect(bbox.overlaps(const Rect.fromLTWH(50, 50, 100, 100)), isTrue);
      expect(bbox.overlaps(const Rect.fromLTWH(200, 200, 50, 50)), isFalse);
    });

    test('도형 스트로크', () {
      final stroke = Stroke(
        id: 'shape-stroke',
        toolType: ToolType.pen,
        color: Colors.blue,
        width: 2.0,
        points: [
          const StrokePoint(x: 0, y: 0, pressure: 1, tilt: 0, timestamp: 0),
          const StrokePoint(x: 100, y: 100, pressure: 1, tilt: 0, timestamp: 16),
        ],
        timestamp: 0,
        isShape: true,
        shapeType: ShapeType.line,
      );

      expect(stroke.isShape, isTrue);
      expect(stroke.shapeType, equals(ShapeType.line));
    });

    test('다양한 ToolType', () {
      final toolTypes = [
        ToolType.pen,
        ToolType.pencil,
        ToolType.marker,
        ToolType.highlighter,
        ToolType.eraser,
      ];

      for (final toolType in toolTypes) {
        final stroke = Stroke(
          id: 'tool-${toolType.name}',
          toolType: toolType,
          color: Colors.black,
          width: 2.0,
          points: [const StrokePoint(x: 0, y: 0, pressure: 0.5, tilt: 0, timestamp: 0)],
          timestamp: 0,
        );

        expect(stroke.toolType, equals(toolType));
      }
    });
  });

  // ========================================
  // 3. StrokeSmoothingService 테스트
  // ========================================
  group('🖌️ StrokeSmoothingService 테스트', () {
    test('스무딩 레벨 변경', () {
      final smoothingService = StrokeSmoothingService.instance;

      smoothingService.level = SmoothingLevel.strong;
      expect(smoothingService.level, equals(SmoothingLevel.strong));

      smoothingService.level = SmoothingLevel.none;
      expect(smoothingService.level, equals(SmoothingLevel.none));

      // 기본값으로 복원
      smoothingService.level = SmoothingLevel.medium;
    });

    test('포인트 필터링', () {
      final smoothingService = StrokeSmoothingService.instance;
      smoothingService.level = SmoothingLevel.medium;
      smoothingService.beginStroke();

      final existingPoints = <StrokePoint>[];

      // 첫 번째 포인트
      const point1 = StrokePoint(x: 0, y: 0, pressure: 0.5, tilt: 0, timestamp: 0);
      final filtered1 = smoothingService.filterPoint(point1, existingPoints);
      expect(filtered1, isNotNull);
      existingPoints.add(filtered1!);

      // 두 번째 포인트 (충분히 먼 거리)
      const point2 = StrokePoint(x: 50, y: 50, pressure: 0.5, tilt: 0, timestamp: 16);
      final filtered2 = smoothingService.filterPoint(point2, existingPoints);
      expect(filtered2, isNotNull);

      print('필터링된 포인트 수: ${existingPoints.length + (filtered2 != null ? 1 : 0)}');
    });

    test('펜 예측 활성화/비활성화', () {
      final smoothingService = StrokeSmoothingService.instance;

      smoothingService.predictionEnabled = true;
      expect(smoothingService.predictionEnabled, isTrue);

      smoothingService.predictionEnabled = false;
      expect(smoothingService.predictionEnabled, isFalse);

      // 기본값으로 복원
      smoothingService.predictionEnabled = true;
    });
  });

  // ========================================
  // 4. ShapeRecognitionService 테스트
  // ========================================
  group('🔷 ShapeRecognitionService 테스트', () {
    test('도형 인식 활성화/비활성화', () {
      final shapeService = ShapeRecognitionService.instance;

      shapeService.enabled = true;
      expect(shapeService.enabled, isTrue);

      shapeService.enabled = false;
      expect(shapeService.enabled, isFalse);
    });

    test('임계값 설정', () {
      final shapeService = ShapeRecognitionService.instance;

      shapeService.threshold = 0.8;
      expect(shapeService.threshold, equals(0.8));

      // 범위 제한 확인
      shapeService.threshold = 0.3; // 너무 낮음
      expect(shapeService.threshold, greaterThanOrEqualTo(0.5));

      shapeService.threshold = 0.99; // 너무 높음
      expect(shapeService.threshold, lessThanOrEqualTo(0.95));

      // 기본값으로 복원
      shapeService.threshold = 0.75;
    });

    test('직선 스트로크 인식', () {
      final shapeService = ShapeRecognitionService.instance;
      shapeService.enabled = true;
      shapeService.threshold = 0.7;

      // 거의 직선에 가까운 포인트들
      final points = <StrokePoint>[];
      for (int i = 0; i <= 20; i++) {
        points.add(StrokePoint(
          x: i * 10.0,
          y: i * 10.0 + (i % 2 == 0 ? 1 : -1), // 약간의 오차
          pressure: 0.5,
          tilt: 0,
          timestamp: i * 16,
        ),);
      }

      final stroke = Stroke(
        id: 'line-test',
        toolType: ToolType.pen,
        color: Colors.black,
        width: 2.0,
        points: points,
        timestamp: 0,
      );

      final result = shapeService.recognize(stroke);
      print('직선 인식 결과: type=${result.type}, confidence=${result.confidence}');

      if (result.isRecognized) {
        expect(result.type, equals(RecognizedShapeType.line));
      }

      shapeService.enabled = false;
    });

    test('비활성화 시 인식 안함', () {
      final shapeService = ShapeRecognitionService.instance;
      shapeService.enabled = false;

      final stroke = _createTestStroke('disabled-test', 10);
      final result = shapeService.recognize(stroke);

      expect(result.type, equals(RecognizedShapeType.none));
    });
  });

  // ========================================
  // 5. JSON 직렬화/역직렬화 테스트
  // ========================================
  group('📄 JSON 직렬화 테스트', () {
    test('Note JSON 왕복 변환', () async {
      final note = _createTestNote('json-test-1', 'JSON 테스트');

      final json = note.toJson();
      final restored = Note.fromJson(json);

      expect(restored.id, equals(note.id));
      expect(restored.title, equals(note.title));
      expect(restored.pageCount, equals(note.pageCount));
      expect(restored.pages[0].strokes.length, equals(note.pages[0].strokes.length));
    });

    test('다중 페이지 노트 JSON 변환', () {
      final note = _createMultiPageNote('multi-json', '다중 페이지', 5);

      final json = note.toJson();
      final restored = Note.fromJson(json);

      expect(restored.pageCount, equals(5));
      for (int i = 0; i < 5; i++) {
        expect(restored.pages[i].pageNumber, equals(i));
      }
    });

    test('레거시 형식 호환성', () {
      // v1 형식 (pages 없이 strokes 직접)
      final legacyJson = {
        'id': 'legacy-note',
        'title': '레거시 노트',
        'strokes': [
          {
            'id': 'legacy-stroke',
            'toolType': 0,
            'color': 0xFF000000,
            'width': 2.0,
            'points': [
              {'x': 10.0, 'y': 20.0, 'pressure': 0.5, 'timestamp': 1000},
            ],
            'timestamp': 1000,
          }
        ],
        'createdAt': DateTime.now().toIso8601String(),
        'modifiedAt': DateTime.now().toIso8601String(),
      };

      final note = Note.fromJson(legacyJson);

      expect(note.id, equals('legacy-note'));
      expect(note.pageCount, equals(1));
      expect(note.strokes.length, equals(1));
    });

    test('파일 저장 및 로드', () async {
      final note = _createTestNote('file-test', '파일 테스트');
      final filePath = '$testBasePath${Platform.pathSeparator}file-test.json';

      // 저장
      await File(filePath).writeAsString(jsonEncode(note.toJson()));

      // 로드
      final loadedJson = await File(filePath).readAsString();
      final loadedNote = Note.fromJson(jsonDecode(loadedJson));

      expect(loadedNote.id, equals(note.id));
      expect(loadedNote.title, equals(note.title));
    });

    test('스트로크 포인트 필압/틸트 데이터 보존', () async {
      final points = <StrokePoint>[];
      for (int i = 0; i < 10; i++) {
        points.add(StrokePoint(
          x: i * 10.0,
          y: i * 5.0,
          pressure: 0.3 + (i / 10) * 0.5,
          tilt: (i / 10) * 0.8,
          timestamp: i * 16,
        ),);
      }

      final stroke = Stroke(
        id: 'pressure-tilt-stroke',
        toolType: ToolType.pen,
        color: Colors.black,
        width: 2.0,
        points: points,
        timestamp: 0,
      );

      final note = Note(
        id: 'pressure-tilt-note',
        title: '필압/틸트 테스트',
        pages: [NotePage(pageNumber: 0, strokes: [stroke])],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      final filePath = '$testBasePath${Platform.pathSeparator}pressure-tilt.json';
      await File(filePath).writeAsString(jsonEncode(note.toJson()));

      final loadedNote = Note.fromJson(jsonDecode(await File(filePath).readAsString()));
      final loadedPoint = loadedNote.pages[0].strokes[0].points[5];
      final originalPoint = points[5];

      expect(loadedPoint.pressure, closeTo(originalPoint.pressure, 0.001));
      expect(loadedPoint.tilt, closeTo(originalPoint.tilt, 0.001));
    });
  });

  // ========================================
  // 6. 서비스 연동 테스트
  // ========================================
  group('🔗 서비스 연동 테스트', () {
    test('노트 생성 → 스무딩 → 저장 플로우', () async {
      // 1. 스무딩 서비스로 포인트 처리
      final smoothingService = StrokeSmoothingService.instance;
      smoothingService.level = SmoothingLevel.medium;
      smoothingService.beginStroke();

      final existingPoints = <StrokePoint>[];
      for (int i = 0; i < 30; i++) {
        final point = StrokePoint(
          x: i * 10.0 + (i % 3 == 0 ? 3 : 0),
          y: i * 8.0 + (i % 4 == 0 ? 2 : 0),
          pressure: 0.4 + (i / 30) * 0.4,
          tilt: 0.1,
          timestamp: i * 16,
        );

        final filtered = smoothingService.filterPoint(point, existingPoints);
        if (filtered != null) {
          existingPoints.add(filtered);
        }
      }

      // 2. 스트로크 생성
      final stroke = Stroke(
        id: 'flow-stroke-1',
        toolType: ToolType.pen,
        color: Colors.blue,
        width: 2.0,
        points: existingPoints,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      // 3. 노트 생성
      final note = Note(
        id: 'flow-note-1',
        title: '연동 테스트 노트',
        pages: [NotePage(pageNumber: 0, strokes: [stroke])],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      // 4. JSON 저장
      final filePath = '$testBasePath${Platform.pathSeparator}flow-test.json';
      await File(filePath).writeAsString(jsonEncode(note.toJson()));

      // 5. 로드 및 검증
      final loadedNote = Note.fromJson(
        jsonDecode(await File(filePath).readAsString()),
      );

      expect(loadedNote.strokes.length, equals(1));
      expect(loadedNote.strokes[0].points.length, equals(existingPoints.length));
      print('연동 테스트 완료: ${existingPoints.length}개 포인트 저장됨');
    });

    test('도형 인식 → 저장 플로우', () async {
      final shapeService = ShapeRecognitionService.instance;
      shapeService.enabled = true;
      shapeService.threshold = 0.7;

      // 직선 포인트 생성
      final linePoints = <StrokePoint>[];
      for (int i = 0; i <= 10; i++) {
        linePoints.add(StrokePoint(
          x: i * 20.0,
          y: i * 20.0,
          pressure: 0.5,
          tilt: 0,
          timestamp: i * 16,
        ),);
      }

      final rawStroke = Stroke(
        id: 'shape-flow-1',
        toolType: ToolType.pen,
        color: Colors.red,
        width: 2.0,
        points: linePoints,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      // 도형 인식 시도
      final result = shapeService.recognize(rawStroke);
      print('도형 인식 결과: type=${result.type}, confidence=${result.confidence}');

      // 노트에 저장
      final note = Note(
        id: 'shape-flow-note',
        title: '도형 인식 테스트',
        pages: [NotePage(pageNumber: 0, strokes: [rawStroke])],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      final filePath = '$testBasePath${Platform.pathSeparator}shape-flow.json';
      await File(filePath).writeAsString(jsonEncode(note.toJson()));

      final loadedNote = Note.fromJson(
        jsonDecode(await File(filePath).readAsString()),
      );

      expect(loadedNote.strokes.length, equals(1));

      shapeService.enabled = false;
    });

    test('다중 페이지 작업 플로우', () async {
      // 1. 빈 노트 생성
      var note = Note(
        id: 'multipage-flow',
        title: '다중 페이지 플로우',
        pages: [
          NotePage(
            pageNumber: 0,
            strokes: [],
            templateIndex: PageTemplate.lined.index,
          ),
        ],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      // 2. 첫 페이지에 스트로크 추가
      final stroke1 = _createTestStroke('mp-s1', 15);
      note = note.copyWith(
        pages: [
          note.pages[0].copyWith(strokes: [stroke1]),
        ],
      );

      // 3. 새 페이지 추가 (템플릿 복사)
      note = note.addPage(fromPageNumber: 0);

      // 4. 두 번째 페이지에 스트로크 추가
      final stroke2 = _createTestStroke('mp-s2', 20);
      final updatedPages = List<NotePage>.from(note.pages);
      updatedPages[1] = updatedPages[1].copyWith(strokes: [stroke2]);
      note = note.copyWith(pages: updatedPages);

      // 5. 책갈피 설정
      note = note.togglePageBookmark(0);

      // 6. 저장
      final filePath = '$testBasePath${Platform.pathSeparator}multipage-flow.json';
      await File(filePath).writeAsString(jsonEncode(note.toJson()));

      // 7. 로드 및 검증
      final loadedNote = Note.fromJson(
        jsonDecode(await File(filePath).readAsString()),
      );

      expect(loadedNote.pageCount, equals(2));
      expect(loadedNote.pages[0].strokes.length, equals(1));
      expect(loadedNote.pages[1].strokes.length, equals(1));
      expect(loadedNote.pages[1].templateIndex, equals(PageTemplate.lined.index));
      expect(loadedNote.isPageBookmarked(0), isTrue);

      print('다중 페이지 플로우 테스트 완료');
    });
  });

  // ========================================
  // 7. 성능 테스트
  // ========================================
  group('⚡ 성능 테스트', () {
    test('대용량 스트로크 (1000개) 저장/로드', () async {
      final strokes = <Stroke>[];
      for (int i = 0; i < 1000; i++) {
        strokes.add(_createTestStroke('perf-$i', 50));
      }

      final note = Note(
        id: 'perf-test',
        title: '성능 테스트',
        pages: [NotePage(pageNumber: 0, strokes: strokes)],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      // 저장 시간 측정
      final saveStopwatch = Stopwatch()..start();
      final filePath = '$testBasePath${Platform.pathSeparator}perf-test.json';
      await File(filePath).writeAsString(jsonEncode(note.toJson()));
      saveStopwatch.stop();

      // 로드 시간 측정
      final loadStopwatch = Stopwatch()..start();
      final loadedNote = Note.fromJson(
        jsonDecode(await File(filePath).readAsString()),
      );
      loadStopwatch.stop();

      final fileSize = await File(filePath).length();

      print('=== 성능 테스트 결과 ===');
      print('스트로크 수: 1000개 (각 50 포인트)');
      print('저장 시간: ${saveStopwatch.elapsedMilliseconds}ms');
      print('로드 시간: ${loadStopwatch.elapsedMilliseconds}ms');
      print('파일 크기: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');

      expect(loadedNote.strokes.length, equals(1000));
      expect(saveStopwatch.elapsedMilliseconds, lessThan(10000));
      expect(loadStopwatch.elapsedMilliseconds, lessThan(10000));
    });

    test('다중 페이지 (100페이지) 처리', () async {
      final pages = <NotePage>[];
      for (int p = 0; p < 100; p++) {
        pages.add(NotePage(
          pageNumber: p,
          strokes: [_createTestStroke('page-$p', 20)],
          templateIndex: p % 4, // 다양한 템플릿
        ),);
      }

      final note = Note(
        id: 'multipage-perf',
        title: '100페이지 테스트',
        pages: pages,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      final stopwatch = Stopwatch()..start();
      final filePath = '$testBasePath${Platform.pathSeparator}100pages.json';
      await File(filePath).writeAsString(jsonEncode(note.toJson()));
      final loadedNote = Note.fromJson(
        jsonDecode(await File(filePath).readAsString()),
      );
      stopwatch.stop();

      print('100페이지 왕복 시간: ${stopwatch.elapsedMilliseconds}ms');
      expect(loadedNote.pageCount, equals(100));
    });

    test('BoundingBox 계산 성능', () {
      final points = <StrokePoint>[];
      for (int i = 0; i < 10000; i++) {
        points.add(StrokePoint(
          x: i.toDouble(),
          y: (i * 2).toDouble(),
          pressure: 0.5,
          tilt: 0,
          timestamp: i,
        ),);
      }

      final stroke = Stroke(
        id: 'bbox-perf',
        toolType: ToolType.pen,
        color: Colors.black,
        width: 2.0,
        points: points,
        timestamp: 0,
      );

      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 1000; i++) {
        stroke.recalculateBoundingBox();
      }
      stopwatch.stop();

      print('BoundingBox 1000회 계산: ${stopwatch.elapsedMilliseconds}ms');
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });
  });

  // ========================================
  // 8. 엣지 케이스 테스트
  // ========================================
  group('🔍 엣지 케이스 테스트', () {
    test('빈 노트 처리', () {
      final note = Note(
        id: 'empty-note',
        title: '빈 노트',
        pages: [NotePage(pageNumber: 0, strokes: [])],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      expect(note.strokes, isEmpty);
      expect(note.pageCount, equals(1));

      final json = note.toJson();
      final restored = Note.fromJson(json);
      expect(restored.strokes, isEmpty);
    });

    test('특수 문자가 포함된 제목', () async {
      final titles = [
        '제목 with "quotes"',
        "제목 with 'apostrophe'",
        '제목\nwith\nnewlines',
        '제목 with unicode: 한글 日本語 🎨',
        'Path/With\\Slashes',
        '',  // 빈 제목
      ];

      for (int i = 0; i < titles.length; i++) {
        final note = Note(
          id: 'special-$i',
          title: titles[i],
          pages: [NotePage(pageNumber: 0, strokes: [])],
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
        );

        final json = note.toJson();
        final restored = Note.fromJson(json);
        expect(restored.title, equals(titles[i]));
      }
    });

    test('마지막 페이지 삭제 시도', () {
      var note = Note(
        id: 'single-page',
        title: '단일 페이지',
        pages: [NotePage(pageNumber: 0, strokes: [])],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      // 마지막 페이지 삭제 시도
      note = note.deletePage(0);

      // 최소 1페이지는 유지되어야 함
      expect(note.pageCount, greaterThanOrEqualTo(1));
    });

    test('잘못된 페이지 인덱스 처리', () {
      var note = Note(
        id: 'invalid-index',
        title: '잘못된 인덱스',
        pages: [
          NotePage(pageNumber: 0, strokes: []),
          NotePage(pageNumber: 1, strokes: []),
        ],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      // 존재하지 않는 인덱스로 삭제 시도
      final beforeCount = note.pageCount;
      note = note.deletePage(99);
      expect(note.pageCount, equals(beforeCount)); // 변화 없음
    });

    test('0 필압 스트로크', () {
      final stroke = Stroke(
        id: 'zero-pressure',
        toolType: ToolType.pen,
        color: Colors.black,
        width: 2.0,
        points: [
          const StrokePoint(x: 0, y: 0, pressure: 0.0, tilt: 0.0, timestamp: 0),
          const StrokePoint(x: 10, y: 10, pressure: 0.0, tilt: 0.0, timestamp: 16),
        ],
        timestamp: 0,
      );

      // 0 필압에서도 최소 굵기 적용
      final width = stroke.getWidthAtPressure(0.0, 0.5);
      expect(width, greaterThan(0));
    });

    test('극단적인 좌표값', () async {
      final stroke = Stroke(
        id: 'extreme-coords',
        toolType: ToolType.pen,
        color: Colors.black,
        width: 2.0,
        points: [
          const StrokePoint(x: -999999, y: -999999, pressure: 0, tilt: 0, timestamp: 0),
          const StrokePoint(x: 999999, y: 999999, pressure: 1, tilt: 1, timestamp: 1),
        ],
        timestamp: 0,
      );

      final note = Note(
        id: 'extreme-note',
        title: '극단적 좌표',
        pages: [NotePage(pageNumber: 0, strokes: [stroke])],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      final json = note.toJson();
      final restored = Note.fromJson(json);

      expect(restored.strokes[0].points[0].x, equals(-999999));
      expect(restored.strokes[0].points[1].x, equals(999999));
    });
  });
}

// ===== 테스트 헬퍼 함수들 =====

Note _createTestNote(String id, String title) {
  final strokes = <Stroke>[];
  for (int i = 0; i < 5; i++) {
    strokes.add(_createTestStroke('$id-stroke-$i', 10));
  }

  return Note(
    id: id,
    title: title,
    pages: [NotePage(pageNumber: 0, strokes: strokes)],
    createdAt: DateTime.now(),
    modifiedAt: DateTime.now(),
  );
}

Note _createMultiPageNote(String id, String title, int pageCount) {
  final pages = <NotePage>[];
  for (int p = 0; p < pageCount; p++) {
    final strokes = <Stroke>[];
    for (int s = 0; s < 3; s++) {
      strokes.add(_createTestStroke('$id-p$p-s$s', 5));
    }
    pages.add(NotePage(pageNumber: p, strokes: strokes));
  }

  return Note(
    id: id,
    title: title,
    pages: pages,
    createdAt: DateTime.now(),
    modifiedAt: DateTime.now(),
  );
}

Stroke _createTestStroke(String id, int pointCount) {
  final points = <StrokePoint>[];
  for (int i = 0; i < pointCount; i++) {
    points.add(StrokePoint(
      x: i * 5.0,
      y: i * 3.0,
      pressure: 0.5 + (i / pointCount) * 0.3,
      tilt: (i / pointCount) * 0.5,
      timestamp: i * 16,
    ),);
  }

  return Stroke(
    id: id,
    toolType: ToolType.pen,
    color: Colors.black,
    width: 2.0,
    points: points,
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
}
