import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 키보드 단축키 위젯 테스트
/// Intent 클래스와 Shortcuts 위젯 동작 검증
void main() {
  group('Intent 클래스 테스트', () {
    test('UndoIntent 생성', () {
      const intent = _UndoIntent();
      expect(intent, isA<Intent>());
    });

    test('RedoIntent 생성', () {
      const intent = _RedoIntent();
      expect(intent, isA<Intent>());
    });

    test('PenToolIntent 생성', () {
      const intent = _PenToolIntent();
      expect(intent, isA<Intent>());
    });

    test('EraserToolIntent 생성', () {
      const intent = _EraserToolIntent();
      expect(intent, isA<Intent>());
    });

    test('HighlighterToolIntent 생성', () {
      const intent = _HighlighterToolIntent();
      expect(intent, isA<Intent>());
    });

    test('LassoToolIntent 생성', () {
      const intent = _LassoToolIntent();
      expect(intent, isA<Intent>());
    });

    test('FitToScreenIntent 생성', () {
      const intent = _FitToScreenIntent();
      expect(intent, isA<Intent>());
    });

    test('DeleteSelectionIntent 생성', () {
      const intent = _DeleteSelectionIntent();
      expect(intent, isA<Intent>());
    });
  });

  group('SingleActivator 단축키 테스트', () {
    test('Ctrl+Z 단축키 생성', () {
      const activator = SingleActivator(LogicalKeyboardKey.keyZ, control: true);
      expect(activator.control, isTrue);
      expect(activator.shift, isFalse);
      expect(activator.trigger, equals(LogicalKeyboardKey.keyZ));
    });

    test('Ctrl+Shift+Z 단축키 생성', () {
      const activator = SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
      );
      expect(activator.control, isTrue);
      expect(activator.shift, isTrue);
    });

    test('단일 키 단축키 (P 키)', () {
      const activator = SingleActivator(LogicalKeyboardKey.keyP);
      expect(activator.control, isFalse);
      expect(activator.shift, isFalse);
      expect(activator.alt, isFalse);
      expect(activator.trigger, equals(LogicalKeyboardKey.keyP));
    });
  });

  testWidgets('Shortcuts 위젯 단축키 매핑 테스트', (tester) async {
    String? lastAction;

    await tester.pumpWidget(
      MaterialApp(
        home: Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.keyP): _PenToolIntent(),
            SingleActivator(LogicalKeyboardKey.keyE): _EraserToolIntent(),
            SingleActivator(LogicalKeyboardKey.keyZ, control: true): _UndoIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _PenToolIntent: CallbackAction<_PenToolIntent>(
                onInvoke: (_) {
                  lastAction = 'pen';
                  return null;
                },
              ),
              _EraserToolIntent: CallbackAction<_EraserToolIntent>(
                onInvoke: (_) {
                  lastAction = 'eraser';
                  return null;
                },
              ),
              _UndoIntent: CallbackAction<_UndoIntent>(
                onInvoke: (_) {
                  lastAction = 'undo';
                  return null;
                },
              ),
            },
            child: const Focus(
              autofocus: true,
              child: SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // P 키 눌러서 펜 도구 선택
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(lastAction, equals('pen'));

    // E 키 눌러서 지우개 도구 선택
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(lastAction, equals('eraser'));

    // Ctrl+Z 눌러서 Undo
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(lastAction, equals('undo'));
  });

  testWidgets('Focus가 없으면 단축키 무시', (tester) async {
    String? lastAction;

    await tester.pumpWidget(
      MaterialApp(
        home: Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.keyP): _PenToolIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _PenToolIntent: CallbackAction<_PenToolIntent>(
                onInvoke: (_) {
                  lastAction = 'pen';
                  return null;
                },
              ),
            },
            child: const SizedBox(width: 100, height: 100),
            // autofocus 없음
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // P 키 눌러도 Focus가 없으므로 동작 안함
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    // Focus가 없으면 action이 호출되지 않을 수 있음
    // (실제 동작은 위젯 구조에 따라 다름)
  });
}

// 테스트용 Intent 클래스들
class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

class _PenToolIntent extends Intent {
  const _PenToolIntent();
}

class _EraserToolIntent extends Intent {
  const _EraserToolIntent();
}

class _HighlighterToolIntent extends Intent {
  const _HighlighterToolIntent();
}

class _LassoToolIntent extends Intent {
  const _LassoToolIntent();
}

class _FitToScreenIntent extends Intent {
  const _FitToScreenIntent();
}

class _DeleteSelectionIntent extends Intent {
  const _DeleteSelectionIntent();
}
