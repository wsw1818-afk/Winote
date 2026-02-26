import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:winote/core/services/note_storage_service.dart';
import 'package:winote/domain/entities/stroke.dart';
import 'package:winote/domain/entities/stroke_point.dart';

/// 실제 파일 I/O를 테스트하는 NoteStorageService 통합 테스트
/// 임시 디렉토리를 사용하여 실제 파일 생성/읽기/삭제를 검증
void main() {
  late Directory tempDir;
  late String testNotesPath;

  setUpAll(() async {
    // 테스트용 임시 디렉토리 생성
    tempDir = await Directory.systemTemp.createTemp('winote_test_');
    testNotesPath = '${tempDir.path}${Platform.pathSeparator}notes';
    await Directory(testNotesPath).create(recursive: true);
  });

  tearDownAll(() async {
    // 테스트 후 임시 디렉토리 정리
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Note JSON 직렬화/역직렬화 통합 테스트', () {
    test('Note를 JSON으로 저장하고 다시 로드', () async {
      // 테스트용 노트 생성
      final note = _createTestNote('test-note-1', 'JSON 테스트 노트');

      // JSON 파일로 저장
      final filePath = '$testNotesPath${Platform.pathSeparator}${note.id}.json';
      final file = File(filePath);
      final jsonString = jsonEncode(note.toJson());
      await file.writeAsString(jsonString);

      // 파일이 실제로 생성되었는지 확인
      expect(await file.exists(), isTrue);
      expect(await file.length(), greaterThan(0));

      // 파일에서 다시 로드
      final loadedJson = await file.readAsString();
      final loadedNote = Note.fromJson(jsonDecode(loadedJson));

      // 데이터 무결성 확인
      expect(loadedNote.id, equals(note.id));
      expect(loadedNote.title, equals(note.title));
      expect(loadedNote.pages.length, equals(note.pages.length));
      expect(loadedNote.pages[0].strokes.length, equals(note.pages[0].strokes.length));
    });

    test('다중 페이지 노트 저장 및 로드', () async {
      final note = _createMultiPageNote('multi-page-1', '다중 페이지 노트', 5);

      final filePath = '$testNotesPath${Platform.pathSeparator}${note.id}.json';
      final file = File(filePath);
      await file.writeAsString(jsonEncode(note.toJson()));

      final loadedJson = await file.readAsString();
      final loadedNote = Note.fromJson(jsonDecode(loadedJson));

      expect(loadedNote.pageCount, equals(5));
      for (int i = 0; i < 5; i++) {
        expect(loadedNote.pages[i].pageNumber, equals(i));
        expect(loadedNote.pages[i].strokes.length, greaterThan(0));
      }
    });

    test('스트로크 포인트 필압/틸트 데이터 보존', () async {
      final note = _createNoteWithPressureAndTilt('pressure-tilt-1');

      final filePath = '$testNotesPath${Platform.pathSeparator}${note.id}.json';
      final file = File(filePath);
      await file.writeAsString(jsonEncode(note.toJson()));

      final loadedNote = Note.fromJson(jsonDecode(await file.readAsString()));

      final originalPoint = note.pages[0].strokes[0].points[0];
      final loadedPoint = loadedNote.pages[0].strokes[0].points[0];

      expect(loadedPoint.pressure, closeTo(originalPoint.pressure, 0.001));
      expect(loadedPoint.tilt, closeTo(originalPoint.tilt, 0.001));
      expect(loadedPoint.x, closeTo(originalPoint.x, 0.001));
      expect(loadedPoint.y, closeTo(originalPoint.y, 0.001));
    });

    test('레거시 형식(v1) 노트 로드 호환성', () async {
      // v1 형식의 JSON (pages 대신 strokes 직접 포함)
      final legacyJson = {
        'id': 'legacy-note-1',
        'title': '레거시 노트',
        'strokes': [
          {
            'id': 'stroke-1',
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

      final filePath = '$testNotesPath${Platform.pathSeparator}legacy-note-1.json';
      final file = File(filePath);
      await file.writeAsString(jsonEncode(legacyJson));

      final loadedNote = Note.fromJson(jsonDecode(await file.readAsString()));

      expect(loadedNote.id, equals('legacy-note-1'));
      expect(loadedNote.pages.length, equals(1));
      expect(loadedNote.pages[0].strokes.length, equals(1));
    });

    test('색상값 ARGB 형식 정확성', () async {
      final colors = [
        Colors.red,
        Colors.blue,
        Colors.green,
        Colors.black,
        Colors.white.withOpacity(0.5),
      ];

      for (int i = 0; i < colors.length; i++) {
        final note = _createNoteWithColor('color-$i', colors[i]);
        final filePath = '$testNotesPath${Platform.pathSeparator}color-$i.json';
        await File(filePath).writeAsString(jsonEncode(note.toJson()));

        final loadedNote = Note.fromJson(
          jsonDecode(await File(filePath).readAsString()),
        );

        expect(
          loadedNote.pages[0].strokes[0].color.value,
          equals(colors[i].value),
        );
      }
    });
  });

  group('파일 시스템 작업 테스트', () {
    test('대량 노트 저장 성능 (100개)', () async {
      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < 100; i++) {
        final note = _createTestNote('bulk-$i', '대량 테스트 $i');
        final filePath = '$testNotesPath${Platform.pathSeparator}bulk-$i.json';
        await File(filePath).writeAsString(jsonEncode(note.toJson()));
      }

      stopwatch.stop();
      print('100개 노트 저장 시간: ${stopwatch.elapsedMilliseconds}ms');

      // 성능 기준: 5초 이내
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));

      // 저장된 파일 수 확인
      final files = await Directory(testNotesPath)
          .list()
          .where((e) => e.path.contains('bulk-'))
          .length;
      expect(files, equals(100));
    });

    test('대용량 노트 저장 (1000개 스트로크)', () async {
      final note = _createLargeNote('large-1', 1000);
      final filePath = '$testNotesPath${Platform.pathSeparator}large-1.json';

      final stopwatch = Stopwatch()..start();
      await File(filePath).writeAsString(jsonEncode(note.toJson()));
      stopwatch.stop();

      print('1000개 스트로크 노트 저장 시간: ${stopwatch.elapsedMilliseconds}ms');

      final fileSize = await File(filePath).length();
      print('파일 크기: ${(fileSize / 1024).toStringAsFixed(2)} KB');

      // 파일 크기 확인 (데이터가 실제로 저장됨)
      expect(fileSize, greaterThan(10000)); // 최소 10KB 이상

      // 로드 테스트
      final loadStopwatch = Stopwatch()..start();
      final loadedNote = Note.fromJson(
        jsonDecode(await File(filePath).readAsString()),
      );
      loadStopwatch.stop();

      print('1000개 스트로크 노트 로드 시간: ${loadStopwatch.elapsedMilliseconds}ms');
      expect(loadedNote.strokes.length, equals(1000));
    });

    test('동시 파일 접근 (병렬 저장/로드)', () async {
      final futures = <Future>[];

      // 10개 노트 동시 저장
      for (int i = 0; i < 10; i++) {
        futures.add(() async {
          final note = _createTestNote('parallel-$i', '병렬 테스트 $i');
          final filePath = '$testNotesPath${Platform.pathSeparator}parallel-$i.json';
          await File(filePath).writeAsString(jsonEncode(note.toJson()));
        }());
      }

      await Future.wait(futures);

      // 동시 로드
      final loadFutures = <Future<Note>>[];
      for (int i = 0; i < 10; i++) {
        loadFutures.add(() async {
          final filePath = '$testNotesPath${Platform.pathSeparator}parallel-$i.json';
          return Note.fromJson(jsonDecode(await File(filePath).readAsString()));
        }());
      }

      final loadedNotes = await Future.wait(loadFutures);
      expect(loadedNotes.length, equals(10));

      for (int i = 0; i < 10; i++) {
        expect(loadedNotes[i].title, equals('병렬 테스트 $i'));
      }
    });

    test('파일 삭제 및 존재 확인', () async {
      final note = _createTestNote('delete-test', '삭제 테스트');
      final filePath = '$testNotesPath${Platform.pathSeparator}delete-test.json';
      final file = File(filePath);

      await file.writeAsString(jsonEncode(note.toJson()));
      expect(await file.exists(), isTrue);

      await file.delete();
      expect(await file.exists(), isFalse);
    });

    test('잘못된 JSON 파일 처리', () async {
      final filePath = '$testNotesPath${Platform.pathSeparator}invalid.json';
      await File(filePath).writeAsString('{ invalid json content }}}');

      expect(
        () async => jsonDecode(await File(filePath).readAsString()),
        throwsFormatException,
      );
    });

    test('빈 파일 처리', () async {
      final filePath = '$testNotesPath${Platform.pathSeparator}empty.json';
      await File(filePath).writeAsString('');

      expect(
        () async => jsonDecode(await File(filePath).readAsString()),
        throwsFormatException,
      );
    });

    test('존재하지 않는 파일 접근', () async {
      final filePath = '$testNotesPath${Platform.pathSeparator}nonexistent.json';
      final file = File(filePath);

      expect(await file.exists(), isFalse);
      expect(() => file.readAsString(), throwsA(isA<FileSystemException>()));
    });
  });

  group('NotePage 기능 통합 테스트', () {
    test('페이지 추가 후 저장/로드', () async {
      var note = _createTestNote('page-add-1', '페이지 추가 테스트');

      // 페이지 추가
      note = note.addPage();
      note = note.addPage();

      expect(note.pageCount, equals(3));

      final filePath = '$testNotesPath${Platform.pathSeparator}page-add-1.json';
      await File(filePath).writeAsString(jsonEncode(note.toJson()));

      final loadedNote = Note.fromJson(
        jsonDecode(await File(filePath).readAsString()),
      );
      expect(loadedNote.pageCount, equals(3));
    });

    test('페이지 삭제 후 저장/로드', () async {
      var note = _createMultiPageNote('page-delete-1', '페이지 삭제 테스트', 5);

      // 중간 페이지 삭제
      note = note.deletePage(2);
      expect(note.pageCount, equals(4));

      final filePath = '$testNotesPath${Platform.pathSeparator}page-delete-1.json';
      await File(filePath).writeAsString(jsonEncode(note.toJson()));

      final loadedNote = Note.fromJson(
        jsonDecode(await File(filePath).readAsString()),
      );
      expect(loadedNote.pageCount, equals(4));

      // 페이지 번호 2가 삭제되었는지 확인
      final pageNumbers = loadedNote.pages.map((p) => p.pageNumber).toList();
      expect(pageNumbers.contains(2), isFalse);
    });

    test('페이지 복제 후 저장/로드', () async {
      var note = _createTestNote('page-dup-1', '페이지 복제 테스트');

      note = note.duplicatePage(0);
      expect(note.pageCount, equals(2));
      expect(
        note.pages[1].strokes.length,
        equals(note.pages[0].strokes.length),
      );

      final filePath = '$testNotesPath${Platform.pathSeparator}page-dup-1.json';
      await File(filePath).writeAsString(jsonEncode(note.toJson()));

      final loadedNote = Note.fromJson(
        jsonDecode(await File(filePath).readAsString()),
      );
      expect(loadedNote.pageCount, equals(2));
    });

    test('책갈피 토글 후 저장/로드', () async {
      var note = _createMultiPageNote('bookmark-1', '책갈피 테스트', 3);

      note = note.togglePageBookmark(0);
      note = note.togglePageBookmark(2);

      expect(note.isPageBookmarked(0), isTrue);
      expect(note.isPageBookmarked(1), isFalse);
      expect(note.isPageBookmarked(2), isTrue);

      final filePath = '$testNotesPath${Platform.pathSeparator}bookmark-1.json';
      await File(filePath).writeAsString(jsonEncode(note.toJson()));

      final loadedNote = Note.fromJson(
        jsonDecode(await File(filePath).readAsString()),
      );
      expect(loadedNote.isPageBookmarked(0), isTrue);
      expect(loadedNote.isPageBookmarked(1), isFalse);
      expect(loadedNote.isPageBookmarked(2), isTrue);
      expect(loadedNote.bookmarkedPages.length, equals(2));
    });

    test('페이지 순서 변경 후 저장/로드', () async {
      var note = _createMultiPageNote('reorder-1', '순서 변경 테스트', 5);

      // 페이지 0을 마지막으로 이동
      note = note.reorderPages(0, 4);

      final filePath = '$testNotesPath${Platform.pathSeparator}reorder-1.json';
      await File(filePath).writeAsString(jsonEncode(note.toJson()));

      final loadedNote = Note.fromJson(
        jsonDecode(await File(filePath).readAsString()),
      );

      // 페이지 번호가 0-4로 재정렬되었는지 확인
      for (int i = 0; i < 5; i++) {
        expect(loadedNote.pages[i].pageNumber, equals(i));
      }
    });
  });

  group('폴더 기능 통합 테스트', () {
    test('폴더 생성 및 노트 이동', () async {
      final folder = NoteFolder(
        id: 'folder-1',
        name: '테스트 폴더',
        colorValue: 0xFF2196F3,
        createdAt: DateTime.now(),
      );

      final note = _createTestNote('folder-note-1', '폴더 내 노트')
          .copyWith(folderId: folder.id);

      expect(note.folderId, equals('folder-1'));

      // 저장/로드
      final filePath = '$testNotesPath${Platform.pathSeparator}folder-note-1.json';
      await File(filePath).writeAsString(jsonEncode(note.toJson()));

      final loadedNote = Note.fromJson(
        jsonDecode(await File(filePath).readAsString()),
      );
      expect(loadedNote.folderId, equals('folder-1'));
    });

    test('폴더에서 루트로 노트 이동', () async {
      final note = _createTestNote('root-move-1', '루트로 이동')
          .copyWith(folderId: 'some-folder');

      final movedNote = note.copyWith(clearFolder: true);
      expect(movedNote.folderId, isNull);

      final filePath = '$testNotesPath${Platform.pathSeparator}root-move-1.json';
      await File(filePath).writeAsString(jsonEncode(movedNote.toJson()));

      final loadedNote = Note.fromJson(
        jsonDecode(await File(filePath).readAsString()),
      );
      expect(loadedNote.folderId, isNull);
    });
  });

  group('태그 및 즐겨찾기 통합 테스트', () {
    test('태그 추가/제거 후 저장/로드', () async {
      var note = _createTestNote('tag-1', '태그 테스트');

      note = note.copyWith(tags: ['flutter', 'dart', '노트']);
      expect(note.tags.length, equals(3));

      final filePath = '$testNotesPath${Platform.pathSeparator}tag-1.json';
      await File(filePath).writeAsString(jsonEncode(note.toJson()));

      final loadedNote = Note.fromJson(
        jsonDecode(await File(filePath).readAsString()),
      );
      expect(loadedNote.tags, containsAll(['flutter', 'dart', '노트']));
    });

    test('즐겨찾기 토글 후 저장/로드', () async {
      var note = _createTestNote('fav-1', '즐겨찾기 테스트');
      expect(note.isFavorite, isFalse);

      note = note.copyWith(isFavorite: true);
      expect(note.isFavorite, isTrue);

      final filePath = '$testNotesPath${Platform.pathSeparator}fav-1.json';
      await File(filePath).writeAsString(jsonEncode(note.toJson()));

      final loadedNote = Note.fromJson(
        jsonDecode(await File(filePath).readAsString()),
      );
      expect(loadedNote.isFavorite, isTrue);
    });
  });

  group('엣지 케이스 및 예외 처리', () {
    test('특수 문자가 포함된 제목', () async {
      final titles = [
        '제목 with "quotes"',
        "제목 with 'apostrophe'",
        '제목\nwith\nnewlines',
        '제목 with unicode: 한글 日本語 🎨',
        'Path/With\\Slashes',
      ];

      for (int i = 0; i < titles.length; i++) {
        final note = _createTestNote('special-$i', titles[i]);
        final filePath = '$testNotesPath${Platform.pathSeparator}special-$i.json';
        await File(filePath).writeAsString(jsonEncode(note.toJson()));

        final loadedNote = Note.fromJson(
          jsonDecode(await File(filePath).readAsString()),
        );
        expect(loadedNote.title, equals(titles[i]));
      }
    });

    test('빈 스트로크 목록', () async {
      final note = Note(
        id: 'empty-strokes',
        title: '빈 스트로크',
        pages: [NotePage(pageNumber: 0, strokes: [])],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      final filePath = '$testNotesPath${Platform.pathSeparator}empty-strokes.json';
      await File(filePath).writeAsString(jsonEncode(note.toJson()));

      final loadedNote = Note.fromJson(
        jsonDecode(await File(filePath).readAsString()),
      );
      expect(loadedNote.strokes, isEmpty);
    });

    test('단일 포인트 스트로크', () async {
      final stroke = Stroke(
        id: 'single-point',
        toolType: ToolType.pen,
        color: Colors.black,
        width: 2.0,
        points: [
          const StrokePoint(x: 100, y: 100, pressure: 0.5, tilt: 0, timestamp: 1000),
        ],
        timestamp: 1000,
      );

      final note = Note(
        id: 'single-point-note',
        title: '단일 포인트',
        pages: [NotePage(pageNumber: 0, strokes: [stroke])],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      final filePath = '$testNotesPath${Platform.pathSeparator}single-point-note.json';
      await File(filePath).writeAsString(jsonEncode(note.toJson()));

      final loadedNote = Note.fromJson(
        jsonDecode(await File(filePath).readAsString()),
      );
      expect(loadedNote.strokes[0].points.length, equals(1));
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
          const StrokePoint(x: 0, y: 0, pressure: 0.5, tilt: 0.5, timestamp: 2),
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

      final filePath = '$testNotesPath${Platform.pathSeparator}extreme-note.json';
      await File(filePath).writeAsString(jsonEncode(note.toJson()));

      final loadedNote = Note.fromJson(
        jsonDecode(await File(filePath).readAsString()),
      );

      expect(loadedNote.strokes[0].points[0].x, equals(-999999));
      expect(loadedNote.strokes[0].points[1].x, equals(999999));
    });

    test('0.0 필압/틸트 값 (기본값 처리)', () async {
      final stroke = Stroke(
        id: 'zero-values',
        toolType: ToolType.pen,
        color: Colors.black,
        width: 2.0,
        points: [
          const StrokePoint(x: 10, y: 10, pressure: 0.0, tilt: 0.0, timestamp: 1000),
        ],
        timestamp: 1000,
      );

      final note = Note(
        id: 'zero-values-note',
        title: '0 값 테스트',
        pages: [NotePage(pageNumber: 0, strokes: [stroke])],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      final filePath = '$testNotesPath${Platform.pathSeparator}zero-values-note.json';
      await File(filePath).writeAsString(jsonEncode(note.toJson()));

      final loadedNote = Note.fromJson(
        jsonDecode(await File(filePath).readAsString()),
      );

      expect(loadedNote.strokes[0].points[0].pressure, equals(0.0));
      expect(loadedNote.strokes[0].points[0].tilt, equals(0.0));
    });
  });

  group('디렉토리 목록 테스트', () {
    test('디렉토리 내 모든 JSON 파일 열거', () async {
      // 테스트용 노트 여러 개 저장
      for (int i = 0; i < 5; i++) {
        final note = _createTestNote('list-$i', '목록 테스트 $i');
        final filePath = '$testNotesPath${Platform.pathSeparator}list-$i.json';
        await File(filePath).writeAsString(jsonEncode(note.toJson()));
      }

      final dir = Directory(testNotesPath);
      final jsonFiles = await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.json'))
          .where((e) => e.path.contains('list-'))
          .toList();

      expect(jsonFiles.length, equals(5));
    });

    test('수정일 기준 정렬', () async {
      final notes = <Note>[];

      for (int i = 0; i < 3; i++) {
        // 각 노트마다 다른 수정일 지정
        final note = Note(
          id: 'sort-$i',
          title: '정렬 테스트 $i',
          pages: [NotePage(pageNumber: 0, strokes: [])],
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now().subtract(Duration(days: i)),
        );
        notes.add(note);

        final filePath = '$testNotesPath${Platform.pathSeparator}sort-$i.json';
        await File(filePath).writeAsString(jsonEncode(note.toJson()));
      }

      // 정렬 (최신순)
      notes.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));

      expect(notes[0].id, equals('sort-0')); // 가장 최근
      expect(notes[2].id, equals('sort-2')); // 가장 오래됨
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

Note _createNoteWithPressureAndTilt(String id) {
  final points = <StrokePoint>[];
  for (int i = 0; i < 20; i++) {
    points.add(StrokePoint(
      x: i * 10.0,
      y: i * 5.0,
      pressure: 0.3 + (i / 20) * 0.6, // 0.3 ~ 0.9
      tilt: (i / 20) * 0.8, // 0 ~ 0.8
      timestamp: i * 16,
    ),);
  }

  final stroke = Stroke(
    id: '$id-stroke',
    toolType: ToolType.pen,
    color: Colors.black,
    width: 2.0,
    points: points,
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );

  return Note(
    id: id,
    title: '필압/틸트 테스트',
    pages: [NotePage(pageNumber: 0, strokes: [stroke])],
    createdAt: DateTime.now(),
    modifiedAt: DateTime.now(),
  );
}

Note _createNoteWithColor(String id, Color color) {
  final stroke = Stroke(
    id: '$id-stroke',
    toolType: ToolType.pen,
    color: color,
    width: 2.0,
    points: [
      const StrokePoint(x: 0, y: 0, pressure: 0.5, tilt: 0, timestamp: 0),
      const StrokePoint(x: 100, y: 100, pressure: 0.5, tilt: 0, timestamp: 16),
    ],
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );

  return Note(
    id: id,
    title: '색상 테스트',
    pages: [NotePage(pageNumber: 0, strokes: [stroke])],
    createdAt: DateTime.now(),
    modifiedAt: DateTime.now(),
  );
}

Note _createLargeNote(String id, int strokeCount) {
  final strokes = <Stroke>[];
  for (int i = 0; i < strokeCount; i++) {
    strokes.add(_createTestStroke('$id-stroke-$i', 50));
  }

  return Note(
    id: id,
    title: '대용량 테스트',
    pages: [NotePage(pageNumber: 0, strokes: strokes)],
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
