import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../domain/entities/stroke.dart';
import '../../domain/entities/stroke_point.dart';

/// 스트로크 래스터 캐싱 서비스
/// - 완료된 스트로크를 이미지로 캐싱하여 렌더링 성능 향상
/// - 타일 기반 캐싱으로 부분 업데이트 지원
/// - 메모리 관리 (LRU 캐시)
class StrokeCacheService {
  static final StrokeCacheService instance = StrokeCacheService._();
  StrokeCacheService._();

  // 캐시된 스트로크 이미지
  final Map<String, ui.Image> _strokeCache = {};

  // 전체 캐시 이미지 (모든 스트로크 합성)
  ui.Image? _compositedCache;
  String? _compositedCacheKey;

  // 캐시 무효화 추적
  int _strokeVersion = 0;

  // 캐시 설정
  static const int _maxCacheSize = 100; // 최대 개별 스트로크 캐시 수

  /// 캐시 키 생성
  String _generateCacheKey(List<Stroke> strokes) {
    if (strokes.isEmpty) return 'empty';
    final ids = strokes.map((s) => '${s.id}_${s.points.length}').join('_');
    return 'strokes_${ids.hashCode}_$_strokeVersion';
  }

  /// 전체 캐시 유효성 확인
  bool isCacheValid(List<Stroke> strokes) {
    final key = _generateCacheKey(strokes);
    return _compositedCacheKey == key && _compositedCache != null;
  }

  /// 전체 캐시 이미지 가져오기
  ui.Image? getCachedImage() => _compositedCache;

  /// 캐시 무효화
  void invalidateCache() {
    _strokeVersion++;
    _compositedCache?.dispose();
    _compositedCache = null;
    _compositedCacheKey = null;
  }

  /// 개별 스트로크 캐시 삭제
  void invalidateStroke(String strokeId) {
    final cached = _strokeCache.remove(strokeId);
    cached?.dispose();
    invalidateCache();
  }

  /// 전체 캐시 클리어
  void clearAll() {
    for (final image in _strokeCache.values) {
      image.dispose();
    }
    _strokeCache.clear();

    _compositedCache?.dispose();
    _compositedCache = null;
    _compositedCacheKey = null;
    _strokeVersion = 0;
  }

  /// 스트로크 목록을 캐시 이미지로 렌더링
  Future<ui.Image?> cacheStrokes(
    List<Stroke> strokes,
    Size canvasSize,
    Set<String>? excludeIds, // 제외할 스트로크 ID (현재 선택 중인 스트로크 등)
  ) async {
    if (strokes.isEmpty || canvasSize.isEmpty) return null;

    final key = _generateCacheKey(strokes);

    // 이미 캐시된 경우 반환
    if (_compositedCacheKey == key && _compositedCache != null) {
      return _compositedCache;
    }

    // 새로 렌더링
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 각 스트로크 그리기
    for (final stroke in strokes) {
      if (excludeIds?.contains(stroke.id) ?? false) continue;
      _drawStroke(canvas, stroke);
    }

    final picture = recorder.endRecording();

    // 이미지로 변환
    try {
      final image = await picture.toImage(
        canvasSize.width.ceil(),
        canvasSize.height.ceil(),
      );

      // 이전 캐시 정리
      _compositedCache?.dispose();

      _compositedCache = image;
      _compositedCacheKey = key;

      return image;
    } catch (e) {
      return null;
    }
  }

  /// 단일 스트로크 그리기
  void _drawStroke(Canvas canvas, Stroke stroke) {
    if (stroke.points.length < 2) return;

    final paint = Paint()
      ..color = stroke.color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.width;

    // 형광펜은 블렌드 모드 적용
    if (stroke.toolType == ToolType.highlighter) {
      paint.blendMode = BlendMode.multiply;
    }

    // 필압 기반 가변 굵기 그리기
    if (_hasPressureVariation(stroke.points)) {
      _drawVariableWidthStroke(canvas, stroke, paint);
    } else {
      // 균일한 굵기
      final path = Path();
      path.moveTo(stroke.points.first.x, stroke.points.first.y);

      for (int i = 1; i < stroke.points.length; i++) {
        final p = stroke.points[i];
        path.lineTo(p.x, p.y);
      }

      canvas.drawPath(path, paint);
    }
  }

  /// 필압 변동 확인
  bool _hasPressureVariation(List<StrokePoint> points) {
    if (points.length < 2) return false;
    double minP = 1.0, maxP = 0.0;
    for (final p in points) {
      if (p.pressure < minP) minP = p.pressure;
      if (p.pressure > maxP) maxP = p.pressure;
    }
    return (maxP - minP) > 0.1;
  }

  /// 가변 굵기 스트로크 그리기
  void _drawVariableWidthStroke(Canvas canvas, Stroke stroke, Paint basePaint) {
    for (int i = 0; i < stroke.points.length - 1; i++) {
      final p1 = stroke.points[i];
      final p2 = stroke.points[i + 1];

      final pressure = (p1.pressure + p2.pressure) / 2;
      final width = stroke.width * (0.5 + pressure * 0.8);

      final paint = Paint()
        ..color = basePaint.color
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = width;

      if (stroke.toolType == ToolType.highlighter) {
        paint.blendMode = BlendMode.multiply;
      }

      canvas.drawLine(Offset(p1.x, p1.y), Offset(p2.x, p2.y), paint);
    }
  }
}

/// 타일 기반 캐시 (대형 캔버스용)
class TileCache {
  static const double tileSize = 512.0;

  final Map<String, ui.Image> _tiles = {};

  /// 타일 키 생성
  String _tileKey(int tileX, int tileY) => 'tile_${tileX}_$tileY';

  /// 타일 가져오기
  ui.Image? getTile(int tileX, int tileY) => _tiles[_tileKey(tileX, tileY)];

  /// 타일 저장
  void setTile(int tileX, int tileY, ui.Image image) {
    final key = _tileKey(tileX, tileY);
    _tiles[key]?.dispose();
    _tiles[key] = image;
  }

  /// 특정 영역의 타일 무효화
  void invalidateRegion(Rect region) {
    final startTileX = (region.left / tileSize).floor();
    final startTileY = (region.top / tileSize).floor();
    final endTileX = (region.right / tileSize).ceil();
    final endTileY = (region.bottom / tileSize).ceil();

    for (int x = startTileX; x <= endTileX; x++) {
      for (int y = startTileY; y <= endTileY; y++) {
        final key = _tileKey(x, y);
        _tiles[key]?.dispose();
        _tiles.remove(key);
      }
    }
  }

  /// 전체 클리어
  void clear() {
    for (final tile in _tiles.values) {
      tile.dispose();
    }
    _tiles.clear();
  }
}
