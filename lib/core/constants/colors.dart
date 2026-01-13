import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary Colors
  static const Color primary = Color(0xFF2196F3);
  static const Color primaryDark = Color(0xFF1976D2);
  static const Color primaryLight = Color(0xFFBBDEFB);

  // Canvas Colors
  static const Color canvasBackground = Color(0xFFFFFFFF);
  static const Color canvasGrid = Color(0xFFE0E0E0);
  static const Color canvasLine = Color(0xFFBDBDBD);
  static const Color canvasDot = Color(0xFFBDBDBD);

  // Pen Colors (기본 팔레트)
  static const List<Color> penPalette = [
    Color(0xFF000000), // 검정
    Color(0xFF424242), // 진회색
    Color(0xFF757575), // 회색
    Color(0xFFD32F2F), // 빨강
    Color(0xFFF57C00), // 주황
    Color(0xFFFBC02D), // 노랑
    Color(0xFF388E3C), // 초록
    Color(0xFF1976D2), // 파랑
    Color(0xFF7B1FA2), // 보라
    Color(0xFF5D4037), // 갈색
    Color(0xFFE91E63), // 분홍
    Color(0xFF00BCD4), // 청록
  ];

  // Highlighter Colors
  static const List<Color> highlighterPalette = [
    Color(0xFFFFEB3B), // 노랑
    Color(0xFF8BC34A), // 연두
    Color(0xFFFF9800), // 주황
    Color(0xFFE91E63), // 분홍
    Color(0xFF03A9F4), // 하늘
    Color(0xFF9C27B0), // 보라
  ];

  // Semantic Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);
}
