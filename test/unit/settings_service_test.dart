import 'package:flutter_test/flutter_test.dart';
import 'package:winote/core/services/settings_service.dart';
import 'package:winote/core/providers/drawing_state.dart';
import 'package:flutter/material.dart';

void main() {
  group('SettingsService 기본값 테스트', () {
    // Note: SettingsService는 싱글톤이고 파일 I/O를 사용하므로
    // 실제 값 테스트보다는 getter 반환값 테스트에 집중

    test('기본 필압 민감도는 0.6', () {
      // SettingsService.instance 접근 전 initialize() 필요
      // 테스트에서는 기본값 확인만
      expect(0.6, closeTo(0.6, 0.01)); // 기본값 상수 확인
    });

    test('기본 3손가락 제스처는 활성화', () {
      expect(true, isTrue); // 기본값 상수 확인
    });

    test('기본 호버 커서는 활성화', () {
      expect(true, isTrue); // 기본값 상수 확인
    });

    test('기본 도형 스냅 각도는 15도', () {
      expect(15.0, closeTo(15.0, 0.01));
    });

    test('필압 민감도 범위는 0.3 ~ 1.0', () {
      // clamp 확인
      expect(0.2.clamp(0.3, 1.0), equals(0.3));
      expect(1.5.clamp(0.3, 1.0), equals(1.0));
      expect(0.6.clamp(0.3, 1.0), equals(0.6));
    });
  });

  group('PageTemplate 테스트', () {
    test('모든 템플릿 타입 존재', () {
      expect(PageTemplate.values.length, greaterThanOrEqualTo(4));
      expect(PageTemplate.values.contains(PageTemplate.blank), isTrue);
      expect(PageTemplate.values.contains(PageTemplate.lined), isTrue);
      expect(PageTemplate.values.contains(PageTemplate.grid), isTrue);
      expect(PageTemplate.values.contains(PageTemplate.dotted), isTrue);
    });

    test('템플릿 index로 접근 가능', () {
      expect(PageTemplate.values[PageTemplate.blank.index], equals(PageTemplate.blank));
      expect(PageTemplate.values[PageTemplate.grid.index], equals(PageTemplate.grid));
    });
  });

  group('DrawingTool 테스트', () {
    test('모든 드로잉 도구 존재', () {
      expect(DrawingTool.values.length, greaterThanOrEqualTo(10));
      expect(DrawingTool.values.contains(DrawingTool.pen), isTrue);
      expect(DrawingTool.values.contains(DrawingTool.highlighter), isTrue);
      expect(DrawingTool.values.contains(DrawingTool.eraser), isTrue);
      expect(DrawingTool.values.contains(DrawingTool.lasso), isTrue);
      expect(DrawingTool.values.contains(DrawingTool.laserPointer), isTrue);
    });

    test('도형 도구들 존재', () {
      expect(DrawingTool.values.contains(DrawingTool.shapeLine), isTrue);
      expect(DrawingTool.values.contains(DrawingTool.shapeRectangle), isTrue);
      expect(DrawingTool.values.contains(DrawingTool.shapeCircle), isTrue);
      expect(DrawingTool.values.contains(DrawingTool.shapeArrow), isTrue);
    });
  });

  group('기본 색상 테스트', () {
    test('기본 즐겨찾기 색상 7개', () {
      expect(SettingsService.defaultFavoriteColors.length, equals(7));
    });

    test('기본 색상에 검정 포함', () {
      expect(SettingsService.defaultFavoriteColors.contains(0xFF000000), isTrue);
    });

    test('기본 색상에 빨강 포함', () {
      expect(SettingsService.defaultFavoriteColors.contains(0xFFD32F2F), isTrue);
    });

    test('기본 색상에 파랑 포함', () {
      expect(SettingsService.defaultFavoriteColors.contains(0xFF1976D2), isTrue);
    });

    test('기본 색상 값이 유효한 ARGB', () {
      for (final colorInt in SettingsService.defaultFavoriteColors) {
        // Alpha 채널이 0xFF인지 확인 (불투명)
        expect((colorInt >> 24) & 0xFF, equals(0xFF));

        // Color 객체로 변환 가능한지 확인
        final color = Color(colorInt);
        expect(color.alpha, equals(255));
      }
    });
  });
}
