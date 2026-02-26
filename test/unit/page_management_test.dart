import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winote/core/services/note_storage_service.dart';
import 'package:winote/core/providers/drawing_state.dart';
import 'package:winote/domain/entities/stroke.dart';
import 'package:winote/domain/entities/stroke_point.dart';

/// 페이지 관리 기능 테스트
void main() {
  group('페이지 추가 기능 테스트', () {
    test('기본 페이지 추가', () {
      final note = Note(
        id: 'test1',
        title: '테스트 노트',
        pages: [NotePage(pageNumber: 0, strokes: [])],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      expect(note.pageCount, equals(1));

      final updatedNote = note.addPage();
      expect(updatedNote.pageCount, equals(2));
      expect(updatedNote.pages[1].pageNumber, equals(1));
    });

    test('템플릿 설정 복사 - grid 템플릿', () {
      // 첫 페이지에 grid 템플릿 설정
      final note = Note(
        id: 'test2',
        title: '템플릿 테스트',
        pages: [
          NotePage(
            pageNumber: 0,
            strokes: [],
            templateIndex: PageTemplate.grid.index,
          ),
        ],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      // 첫 페이지 템플릿 확인
      expect(note.pages[0].templateIndex, equals(PageTemplate.grid.index));

      // 새 페이지 추가 (템플릿 복사)
      final updatedNote = note.addPage(fromPageNumber: 0);

      // 새 페이지에 템플릿이 복사되었는지 확인
      expect(updatedNote.pageCount, equals(2));
      expect(updatedNote.pages[1].templateIndex, equals(PageTemplate.grid.index));
    });

    test('템플릿 설정 복사 - lined 템플릿', () {
      final note = Note(
        id: 'test3',
        title: '라인 템플릿 테스트',
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

      final updatedNote = note.addPage(fromPageNumber: 0);

      expect(updatedNote.pages[1].templateIndex, equals(PageTemplate.lined.index));
    });

    test('오버레이 템플릿도 복사됨', () {
      final note = Note(
        id: 'test4',
        title: '오버레이 테스트',
        pages: [
          NotePage(
            pageNumber: 0,
            strokes: [],
            templateIndex: PageTemplate.blank.index,
            overlayTemplateIndex: PageTemplate.dotted.index,
          ),
        ],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      final updatedNote = note.addPage(fromPageNumber: 0);

      expect(updatedNote.pages[1].templateIndex, equals(PageTemplate.blank.index));
      expect(updatedNote.pages[1].overlayTemplateIndex, equals(PageTemplate.dotted.index));
    });

    test('배경 이미지는 복사되지 않음', () {
      final note = Note(
        id: 'test5',
        title: '배경 이미지 테스트',
        pages: [
          NotePage(
            pageNumber: 0,
            strokes: [],
            templateIndex: PageTemplate.grid.index,
            backgroundImagePath: '/path/to/image.png',
          ),
        ],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      final updatedNote = note.addPage(fromPageNumber: 0);

      // 템플릿은 복사되지만 배경 이미지는 복사되지 않음
      expect(updatedNote.pages[1].templateIndex, equals(PageTemplate.grid.index));
      expect(updatedNote.pages[1].backgroundImagePath, isNull);
    });

    test('fromPageNumber 없이 추가하면 빈 템플릿 (Note.addPage)', () {
      // Note.addPage()는 fromPageNumber 없이 호출하면 템플릿 없음
      // 하지만 EditorPage._addNewPage()는 UI 템플릿을 직접 사용함
      final note = Note(
        id: 'test6',
        title: '빈 템플릿 테스트',
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

      // Note.addPage() - fromPageNumber 없이 호출
      final updatedNote = note.addPage();

      // Note 모델의 addPage()는 fromPageNumber 없으면 템플릿 없음
      expect(updatedNote.pages[1].templateIndex, isNull);
    });

    test('여러 페이지 연속 추가', () {
      var note = Note(
        id: 'test7',
        title: '연속 추가 테스트',
        pages: [
          NotePage(
            pageNumber: 0,
            strokes: [],
            templateIndex: PageTemplate.grid.index,
          ),
        ],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      // 5페이지 추가
      for (int i = 0; i < 5; i++) {
        note = note.addPage(fromPageNumber: note.pages.last.pageNumber);
      }

      expect(note.pageCount, equals(6));

      // 모든 페이지가 grid 템플릿을 가지고 있는지 확인
      for (final page in note.pages) {
        expect(page.templateIndex, equals(PageTemplate.grid.index));
      }
    });
  });

  group('페이지 삭제 기능 테스트', () {
    test('기본 페이지 삭제', () {
      final note = Note(
        id: 'test10',
        title: '삭제 테스트',
        pages: [
          NotePage(pageNumber: 0, strokes: []),
          NotePage(pageNumber: 1, strokes: []),
          NotePage(pageNumber: 2, strokes: []),
        ],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      expect(note.pageCount, equals(3));

      final updatedNote = note.deletePage(1);
      expect(updatedNote.pageCount, equals(2));
    });

    test('마지막 페이지는 삭제할 수 없음', () {
      final note = Note(
        id: 'test11',
        title: '마지막 페이지 테스트',
        pages: [NotePage(pageNumber: 0, strokes: [])],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      final updatedNote = note.deletePage(0);

      // 페이지가 1개뿐이면 삭제되지 않음
      expect(updatedNote.pageCount, equals(1));
    });

    test('스트로크가 있는 페이지 삭제', () {
      final stroke = Stroke(
        id: 'stroke1',
        points: [const StrokePoint(x: 10, y: 10, pressure: 0.5, tilt: 0, timestamp: 0)],
        color: Colors.black,
        width: 2.0,
        toolType: ToolType.pen,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final note = Note(
        id: 'test12',
        title: '스트로크 삭제 테스트',
        pages: [
          NotePage(pageNumber: 0, strokes: [stroke]),
          NotePage(pageNumber: 1, strokes: []),
        ],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      final updatedNote = note.deletePage(0);
      expect(updatedNote.pageCount, equals(1));
      expect(updatedNote.pages[0].pageNumber, equals(1));
    });

    test('첫 번째 페이지 삭제', () {
      final note = Note(
        id: 'test13',
        title: '첫 페이지 삭제 테스트',
        pages: [
          NotePage(pageNumber: 0, strokes: [], templateIndex: PageTemplate.grid.index),
          NotePage(pageNumber: 1, strokes: [], templateIndex: PageTemplate.lined.index),
        ],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      final updatedNote = note.deletePage(0);
      expect(updatedNote.pageCount, equals(1));
      expect(updatedNote.pages[0].templateIndex, equals(PageTemplate.lined.index));
    });

    test('중간 페이지 삭제', () {
      final note = Note(
        id: 'test14',
        title: '중간 페이지 삭제 테스트',
        pages: [
          NotePage(pageNumber: 0, strokes: []),
          NotePage(pageNumber: 1, strokes: []),
          NotePage(pageNumber: 2, strokes: []),
          NotePage(pageNumber: 3, strokes: []),
        ],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      final updatedNote = note.deletePage(2);
      expect(updatedNote.pageCount, equals(3));

      // 페이지 번호 확인 (0, 1, 3)
      expect(updatedNote.pages.map((p) => p.pageNumber).toList(), containsAll([0, 1, 3]));
    });
  });

  group('페이지 복제 기능 테스트', () {
    test('페이지 복제 시 템플릿 복사', () {
      final note = Note(
        id: 'test20',
        title: '복제 테스트',
        pages: [
          NotePage(
            pageNumber: 0,
            strokes: [],
            templateIndex: PageTemplate.grid.index,
            overlayTemplateIndex: PageTemplate.dotted.index,
          ),
        ],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      final updatedNote = note.duplicatePage(0);

      expect(updatedNote.pageCount, equals(2));
      expect(updatedNote.pages[1].templateIndex, equals(PageTemplate.grid.index));
      expect(updatedNote.pages[1].overlayTemplateIndex, equals(PageTemplate.dotted.index));
    });

    test('페이지 복제 시 스트로크 복사', () {
      final stroke = Stroke(
        id: 'stroke1',
        points: [
          const StrokePoint(x: 10, y: 10, pressure: 0.5, tilt: 0, timestamp: 0),
          const StrokePoint(x: 20, y: 20, pressure: 0.5, tilt: 0, timestamp: 1),
        ],
        color: Colors.blue,
        width: 3.0,
        toolType: ToolType.pen,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final note = Note(
        id: 'test21',
        title: '스트로크 복제 테스트',
        pages: [
          NotePage(pageNumber: 0, strokes: [stroke]),
        ],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      final updatedNote = note.duplicatePage(0);

      expect(updatedNote.pages[1].strokes.length, equals(1));
      expect(updatedNote.pages[1].strokes[0].color, equals(Colors.blue));
      expect(updatedNote.pages[1].strokes[0].points.length, equals(2));

      // ID는 다름 (복제본)
      expect(updatedNote.pages[1].strokes[0].id, isNot(equals(stroke.id)));
    });
  });
}
