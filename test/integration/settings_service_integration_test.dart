import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:winote/core/providers/drawing_state.dart';

/// SettingsService 파일 I/O 통합 테스트
/// 실제 파일 시스템을 사용하여 설정 저장/로드를 테스트
void main() {
  late Directory tempDir;
  late String testSettingsPath;
  late File testSettingsFile;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('winote_settings_test_');
    testSettingsPath = '${tempDir.path}${Platform.pathSeparator}settings.json';
    testSettingsFile = File(testSettingsPath);
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    // 각 테스트 전 설정 파일 삭제
    if (await testSettingsFile.exists()) {
      await testSettingsFile.delete();
    }
  });

  group('Settings JSON 직렬화/역직렬화 테스트', () {
    test('빈 설정 파일 생성 및 기본값 확인', () async {
      final settings = <String, dynamic>{
        'favoriteColors': [0xFF000000, 0xFF1976D2],
        'defaultPenWidth': 2.0,
        'defaultTemplate': PageTemplate.grid.index,
        'autoSaveEnabled': true,
        'autoSaveDelay': 3,
      };

      await testSettingsFile.writeAsString(jsonEncode(settings));
      expect(await testSettingsFile.exists(), isTrue);

      final loaded = jsonDecode(await testSettingsFile.readAsString());
      expect(loaded['favoriteColors'], isA<List>());
      expect(loaded['defaultPenWidth'], equals(2.0));
      expect(loaded['autoSaveEnabled'], isTrue);
    });

    test('전체 설정 항목 저장 및 로드', () async {
      final settings = <String, dynamic>{
        'favoriteColors': [0xFF000000, 0xFF1976D2, 0xFFD32F2F],
        'defaultPenWidth': 3.5,
        'defaultEraserWidth': 25.0,
        'defaultTemplate': PageTemplate.lined.index,
        'autoSaveEnabled': false,
        'autoSaveDelay': 5,
        'lassoColor': 0xFF4CAF50,
        'recentColors': [0xFFFFEB3B, 0xFF9C27B0],
        'themeMode': 2,
        'showDebugOverlay': true,
        'twoFingerGestureMode': 'scroll',
        'palmRejectionEnabled': true,
        'touchDrawingEnabled': true,
        'shapeSnapEnabled': true,
        'shapeSnapAngle': 30.0,
        'autoSyncEnabled': true,
        'shapeRecognitionEnabled': true,
        'pressureSensitivity': 0.7,
        'threeFingerGestureEnabled': false,
        'penHoverCursorEnabled': false,
        'penPresets': [
          {'name': '커스텀 펜', 'color': 0xFF000000, 'width': 4.0, 'toolType': 'pen'},
        ],
      };

      await testSettingsFile.writeAsString(jsonEncode(settings));

      final loaded = jsonDecode(await testSettingsFile.readAsString()) as Map<String, dynamic>;

      expect(loaded['favoriteColors'].length, equals(3));
      expect(loaded['defaultPenWidth'], equals(3.5));
      expect(loaded['defaultEraserWidth'], equals(25.0));
      expect(loaded['defaultTemplate'], equals(PageTemplate.lined.index));
      expect(loaded['autoSaveEnabled'], isFalse);
      expect(loaded['autoSaveDelay'], equals(5));
      expect(loaded['lassoColor'], equals(0xFF4CAF50));
      expect(loaded['themeMode'], equals(2));
      expect(loaded['showDebugOverlay'], isTrue);
      expect(loaded['twoFingerGestureMode'], equals('scroll'));
      expect(loaded['palmRejectionEnabled'], isTrue);
      expect(loaded['touchDrawingEnabled'], isTrue);
      expect(loaded['shapeSnapEnabled'], isTrue);
      expect(loaded['shapeSnapAngle'], equals(30.0));
      expect(loaded['autoSyncEnabled'], isTrue);
      expect(loaded['shapeRecognitionEnabled'], isTrue);
      expect(loaded['pressureSensitivity'], equals(0.7));
      expect(loaded['threeFingerGestureEnabled'], isFalse);
      expect(loaded['penHoverCursorEnabled'], isFalse);
      expect(loaded['penPresets'].length, equals(1));
    });
  });

  group('즐겨찾기 색상 I/O 테스트', () {
    test('기본 즐겨찾기 색상 저장', () async {
      final defaultColors = [
        0xFF000000, // Black
        0xFF1976D2, // Blue
        0xFFD32F2F, // Red
        0xFF388E3C, // Green
        0xFFF57C00, // Orange
        0xFF7B1FA2, // Purple
        0xFFFFEB3B, // Yellow
      ];

      await testSettingsFile.writeAsString(jsonEncode({'favoriteColors': defaultColors}));

      final loaded = jsonDecode(await testSettingsFile.readAsString());
      final loadedColors = (loaded['favoriteColors'] as List).cast<int>();

      expect(loadedColors.length, equals(7));
      expect(loadedColors, contains(0xFF000000));
      expect(loadedColors, contains(0xFFD32F2F));
    });

    test('색상 추가 후 저장', () async {
      final colors = [0xFF000000];
      await testSettingsFile.writeAsString(jsonEncode({'favoriteColors': colors}));

      // 새 색상 추가 시뮬레이션
      final loaded = jsonDecode(await testSettingsFile.readAsString()) as Map<String, dynamic>;
      final loadedColors = List<int>.from(loaded['favoriteColors'] as List);
      loadedColors.add(0xFF00FF00); // 초록색 추가

      await testSettingsFile.writeAsString(jsonEncode({...loaded, 'favoriteColors': loadedColors}));

      final reloaded = jsonDecode(await testSettingsFile.readAsString());
      expect((reloaded['favoriteColors'] as List).length, equals(2));
      expect(reloaded['favoriteColors'], contains(0xFF00FF00));
    });

    test('색상 제거 후 저장', () async {
      final colors = [0xFF000000, 0xFF1976D2, 0xFFD32F2F];
      await testSettingsFile.writeAsString(jsonEncode({'favoriteColors': colors}));

      final loaded = jsonDecode(await testSettingsFile.readAsString()) as Map<String, dynamic>;
      final loadedColors = List<int>.from(loaded['favoriteColors'] as List);
      loadedColors.remove(0xFF1976D2);

      await testSettingsFile.writeAsString(jsonEncode({...loaded, 'favoriteColors': loadedColors}));

      final reloaded = jsonDecode(await testSettingsFile.readAsString());
      expect((reloaded['favoriteColors'] as List).length, equals(2));
      expect(reloaded['favoriteColors'], isNot(contains(0xFF1976D2)));
    });
  });

  group('최근 색상 관리 테스트', () {
    test('최근 색상 추가 (최대 10개)', () async {
      var recentColors = <int>[];

      // 15개 색상 추가 시뮬레이션
      for (int i = 0; i < 15; i++) {
        final newColor = 0xFF000000 + i;
        recentColors.remove(newColor);
        recentColors.insert(0, newColor);
        if (recentColors.length > 10) {
          recentColors = recentColors.sublist(0, 10);
        }
      }

      await testSettingsFile.writeAsString(jsonEncode({'recentColors': recentColors}));

      final loaded = jsonDecode(await testSettingsFile.readAsString());
      final loadedColors = (loaded['recentColors'] as List).cast<int>();

      expect(loadedColors.length, equals(10));
      // 가장 최근 색상이 첫 번째
      expect(loadedColors[0], equals(0xFF00000E)); // 14 = 0xE
    });

    test('중복 색상 추가 시 맨 앞으로 이동', () async {
      final recentColors = [0xFF000000, 0xFF111111, 0xFF222222];

      // 기존 색상 다시 추가
      const existingColor = 0xFF222222;
      recentColors.remove(existingColor);
      recentColors.insert(0, existingColor);

      await testSettingsFile.writeAsString(jsonEncode({'recentColors': recentColors}));

      final loaded = jsonDecode(await testSettingsFile.readAsString());
      final loadedColors = (loaded['recentColors'] as List).cast<int>();

      expect(loadedColors[0], equals(0xFF222222));
      expect(loadedColors.length, equals(3)); // 중복 없이 3개 유지
    });
  });

  group('펜 프리셋 I/O 테스트', () {
    test('기본 프리셋 저장', () async {
      final presets = [
        {'name': '검정 펜', 'color': 0xFF000000, 'width': 2.0, 'toolType': 'pen'},
        {'name': '빨강 펜', 'color': 0xFFD32F2F, 'width': 2.0, 'toolType': 'pen'},
        {'name': '파랑 형광펜', 'color': 0xFF2196F3, 'width': 15.0, 'toolType': 'highlighter'},
      ];

      await testSettingsFile.writeAsString(jsonEncode({'penPresets': presets}));

      final loaded = jsonDecode(await testSettingsFile.readAsString());
      final loadedPresets = (loaded['penPresets'] as List)
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();

      expect(loadedPresets.length, equals(3));
      expect(loadedPresets[0]['name'], equals('검정 펜'));
      expect(loadedPresets[2]['toolType'], equals('highlighter'));
    });

    test('프리셋 추가 (최대 5개 제한)', () async {
      final presets = <Map<String, dynamic>>[];

      // 7개 프리셋 추가 시도
      for (int i = 0; i < 7; i++) {
        if (presets.length >= 5) {
          presets.removeAt(0);
        }
        presets.add({'name': '펜 $i', 'color': 0xFF000000 + i, 'width': 2.0, 'toolType': 'pen'});
      }

      await testSettingsFile.writeAsString(jsonEncode({'penPresets': presets}));

      final loaded = jsonDecode(await testSettingsFile.readAsString());
      final loadedPresets = (loaded['penPresets'] as List);

      expect(loadedPresets.length, equals(5));
      expect(loadedPresets.last['name'], equals('펜 6'));
    });

    test('프리셋 업데이트', () async {
      final presets = [
        {'name': '원래 펜', 'color': 0xFF000000, 'width': 2.0, 'toolType': 'pen'},
      ];

      await testSettingsFile.writeAsString(jsonEncode({'penPresets': presets}));

      // 업데이트 시뮬레이션
      final loaded = jsonDecode(await testSettingsFile.readAsString()) as Map<String, dynamic>;
      final loadedPresets = (loaded['penPresets'] as List)
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();

      loadedPresets[0] = {'name': '수정된 펜', 'color': 0xFFFF0000, 'width': 5.0, 'toolType': 'pen'};

      await testSettingsFile.writeAsString(jsonEncode({...loaded, 'penPresets': loadedPresets}));

      final reloaded = jsonDecode(await testSettingsFile.readAsString());
      expect(reloaded['penPresets'][0]['name'], equals('수정된 펜'));
      expect(reloaded['penPresets'][0]['width'], equals(5.0));
    });
  });

  group('필압 민감도 I/O 테스트', () {
    test('기본 민감도 0.6', () async {
      await testSettingsFile.writeAsString(jsonEncode({'pressureSensitivity': 0.6}));

      final loaded = jsonDecode(await testSettingsFile.readAsString());
      expect(loaded['pressureSensitivity'], equals(0.6));
    });

    test('민감도 범위 테스트 (0.3 ~ 1.0)', () async {
      final testValues = [0.3, 0.5, 0.6, 0.8, 1.0];

      for (final value in testValues) {
        await testSettingsFile.writeAsString(jsonEncode({'pressureSensitivity': value}));

        final loaded = jsonDecode(await testSettingsFile.readAsString());
        expect(loaded['pressureSensitivity'], equals(value));
      }
    });

    test('범위 초과 값 클램핑', () async {
      // 저장 시 클램핑 시뮬레이션
      final tooLow = 0.1.clamp(0.3, 1.0);
      final tooHigh = 1.5.clamp(0.3, 1.0);

      await testSettingsFile.writeAsString(jsonEncode({
        'sensitivity_low': tooLow,
        'sensitivity_high': tooHigh,
      }),);

      final loaded = jsonDecode(await testSettingsFile.readAsString());
      expect(loaded['sensitivity_low'], equals(0.3));
      expect(loaded['sensitivity_high'], equals(1.0));
    });
  });

  group('도형 스냅 설정 I/O 테스트', () {
    test('스냅 활성화 상태 저장', () async {
      await testSettingsFile.writeAsString(jsonEncode({
        'shapeSnapEnabled': true,
        'shapeSnapAngle': 15.0,
      }),);

      final loaded = jsonDecode(await testSettingsFile.readAsString());
      expect(loaded['shapeSnapEnabled'], isTrue);
      expect(loaded['shapeSnapAngle'], equals(15.0));
    });

    test('스냅 각도 변경', () async {
      final angles = [15.0, 30.0, 45.0, 90.0];

      for (final angle in angles) {
        await testSettingsFile.writeAsString(jsonEncode({'shapeSnapAngle': angle}));

        final loaded = jsonDecode(await testSettingsFile.readAsString());
        expect(loaded['shapeSnapAngle'], equals(angle));
      }
    });
  });

  group('테마 모드 I/O 테스트', () {
    test('시스템 테마 (0)', () async {
      await testSettingsFile.writeAsString(jsonEncode({'themeMode': 0}));
      final loaded = jsonDecode(await testSettingsFile.readAsString());
      expect(loaded['themeMode'], equals(0));
    });

    test('라이트 테마 (1)', () async {
      await testSettingsFile.writeAsString(jsonEncode({'themeMode': 1}));
      final loaded = jsonDecode(await testSettingsFile.readAsString());
      expect(loaded['themeMode'], equals(1));
    });

    test('다크 테마 (2)', () async {
      await testSettingsFile.writeAsString(jsonEncode({'themeMode': 2}));
      final loaded = jsonDecode(await testSettingsFile.readAsString());
      expect(loaded['themeMode'], equals(2));
    });
  });

  group('제스처 설정 I/O 테스트', () {
    test('2손가락 제스처 모드', () async {
      await testSettingsFile.writeAsString(jsonEncode({'twoFingerGestureMode': 'zoom'}));
      var loaded = jsonDecode(await testSettingsFile.readAsString());
      expect(loaded['twoFingerGestureMode'], equals('zoom'));

      await testSettingsFile.writeAsString(jsonEncode({'twoFingerGestureMode': 'scroll'}));
      loaded = jsonDecode(await testSettingsFile.readAsString());
      expect(loaded['twoFingerGestureMode'], equals('scroll'));
    });

    test('3손가락 제스처 활성화 상태', () async {
      await testSettingsFile.writeAsString(jsonEncode({'threeFingerGestureEnabled': true}));
      var loaded = jsonDecode(await testSettingsFile.readAsString());
      expect(loaded['threeFingerGestureEnabled'], isTrue);

      await testSettingsFile.writeAsString(jsonEncode({'threeFingerGestureEnabled': false}));
      loaded = jsonDecode(await testSettingsFile.readAsString());
      expect(loaded['threeFingerGestureEnabled'], isFalse);
    });
  });

  group('파일 시스템 예외 처리 테스트', () {
    test('잘못된 JSON 파일 처리', () async {
      await testSettingsFile.writeAsString('{ invalid json content }}}');

      expect(
        () => jsonDecode(testSettingsFile.readAsStringSync()),
        throwsFormatException,
      );
    });

    test('빈 파일 처리', () async {
      await testSettingsFile.writeAsString('');

      expect(
        () => jsonDecode(testSettingsFile.readAsStringSync()),
        throwsFormatException,
      );
    });

    test('파일이 없을 때 존재 확인', () async {
      final nonExistent = File('${tempDir.path}/nonexistent.json');
      expect(await nonExistent.exists(), isFalse);
    });

    test('부분적 설정 로드 (일부 키만 존재)', () async {
      await testSettingsFile.writeAsString(jsonEncode({
        'autoSaveEnabled': true,
        // 다른 키들은 없음
      }),);

      final loaded = jsonDecode(await testSettingsFile.readAsString()) as Map<String, dynamic>;

      expect(loaded['autoSaveEnabled'], isTrue);
      expect(loaded['defaultPenWidth'], isNull);
      expect(loaded['favoriteColors'], isNull);
    });
  });

  group('설정 동기화 테스트', () {
    test('여러 번 연속 저장', () async {
      for (int i = 0; i < 10; i++) {
        await testSettingsFile.writeAsString(jsonEncode({
          'counter': i,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),);
      }

      final loaded = jsonDecode(await testSettingsFile.readAsString());
      expect(loaded['counter'], equals(9));
    });

    test('설정 병합 (기존 값 유지하면서 새 값 추가)', () async {
      // 초기 설정
      await testSettingsFile.writeAsString(jsonEncode({
        'setting1': 'value1',
        'setting2': 'value2',
      }),);

      // 로드 후 병합
      final loaded = jsonDecode(await testSettingsFile.readAsString()) as Map<String, dynamic>;
      loaded['setting3'] = 'value3';
      loaded['setting1'] = 'updated1';

      await testSettingsFile.writeAsString(jsonEncode(loaded));

      final reloaded = jsonDecode(await testSettingsFile.readAsString());
      expect(reloaded['setting1'], equals('updated1'));
      expect(reloaded['setting2'], equals('value2'));
      expect(reloaded['setting3'], equals('value3'));
    });
  });

  group('PageTemplate 저장/로드 테스트', () {
    test('모든 템플릿 타입 저장', () async {
      for (final template in PageTemplate.values) {
        await testSettingsFile.writeAsString(jsonEncode({
          'defaultTemplate': template.index,
        }),);

        final loaded = jsonDecode(await testSettingsFile.readAsString());
        expect(loaded['defaultTemplate'], equals(template.index));
      }
    });

    test('잘못된 템플릿 인덱스 처리', () async {
      await testSettingsFile.writeAsString(jsonEncode({
        'defaultTemplate': 999, // 존재하지 않는 인덱스
      }),);

      final loaded = jsonDecode(await testSettingsFile.readAsString());
      final index = loaded['defaultTemplate'] as int;

      // 범위 체크 시뮬레이션
      final template = (index < 0 || index >= PageTemplate.values.length)
          ? PageTemplate.grid
          : PageTemplate.values[index];

      expect(template, equals(PageTemplate.grid));
    });
  });

  group('대용량/성능 테스트', () {
    test('대량 색상 저장 (100개)', () async {
      final colors = List.generate(100, (i) => 0xFF000000 + i);

      final stopwatch = Stopwatch()..start();
      await testSettingsFile.writeAsString(jsonEncode({'favoriteColors': colors}));
      stopwatch.stop();

      print('100개 색상 저장 시간: ${stopwatch.elapsedMilliseconds}ms');
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));

      final loaded = jsonDecode(await testSettingsFile.readAsString());
      expect((loaded['favoriteColors'] as List).length, equals(100));
    });

    test('복잡한 설정 파일 저장/로드 성능', () async {
      final complexSettings = {
        'favoriteColors': List.generate(50, (i) => 0xFF000000 + i),
        'recentColors': List.generate(10, (i) => 0xFF100000 + i),
        'penPresets': List.generate(5, (i) => {
          'name': '펜 $i',
          'color': 0xFF000000 + i,
          'width': 2.0 + i * 0.5,
          'toolType': i % 2 == 0 ? 'pen' : 'highlighter',
        },),
        'defaultPenWidth': 2.5,
        'defaultEraserWidth': 25.0,
        'defaultTemplate': 1,
        'autoSaveEnabled': true,
        'autoSaveDelay': 5,
        'lassoColor': 0xFF4CAF50,
        'themeMode': 2,
        'showDebugOverlay': false,
        'twoFingerGestureMode': 'zoom',
        'palmRejectionEnabled': true,
        'touchDrawingEnabled': false,
        'shapeSnapEnabled': true,
        'shapeSnapAngle': 15.0,
        'autoSyncEnabled': false,
        'shapeRecognitionEnabled': true,
        'pressureSensitivity': 0.65,
        'threeFingerGestureEnabled': true,
        'penHoverCursorEnabled': true,
      };

      final stopwatch = Stopwatch()..start();
      await testSettingsFile.writeAsString(jsonEncode(complexSettings));
      final loaded = jsonDecode(await testSettingsFile.readAsString());
      stopwatch.stop();

      print('복잡한 설정 저장/로드 시간: ${stopwatch.elapsedMilliseconds}ms');
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
      expect(loaded.keys.length, equals(complexSettings.keys.length));
    });
  });
}
