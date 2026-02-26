import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../domain/entities/stroke.dart';
import '../../domain/entities/stroke_point.dart';

/// 스트로크 래스터 캐싱 서비스
/// - 완료된 스트로크를 이미지로 캐싱하여 렌더링 성능 향상
/// - 전체 스트로크 합성 캐시로 빠른 재그리기 지원
class StrokeCacheService {
  static final StrokeCacheService instance = StrokeCacheService._();
  StrokeCacheService._();

  // 전체 캐시 이미지 (모든 스트로크 합성)
  ui.Image? _compositedCache;
  String? _compositedCacheKey;

  // 캐시 무효화 추적
  int _strokeVersion = 0;

  /// 캐시 키 생성 (색상/굵기/타입 포함하여 변경 감지)
  /// 주의: hashCode는 충돌 가능성이 있으나, _strokeVersion으로 완화됨
  /// 대용량 노트에서 성능 우선으로 hashCode 사용 (SHA 해시는 성능 저하)
  String _generateCacheKey(List<Stroke> strokes) {
    if (strokes.isEmpty) return 'empty_$_strokeVersion';
    // 색상, 굵기, 타입까지 포함하여 속성 변경 시 캐시 무효화
    final ids = strokes.map((s) =>
      '${s.id}_${s.points.length}_${s.color.value}_${s.width.toInt()}_${s.toolType.index}',
    ).join('_');
    // strokeVersion을 항상 포함하여 충돌 시에도 invalidate 가능
    return 'strokes_${strokes.length}_${ids.hashCode}_$_strokeVersion';
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

  /// 개별 스트로크 캐시 삭제 (전체 캐시 무효화)
  void invalidateStroke(String strokeId) {
    invalidateCache();
  }

  /// 전체 캐시 클리어
  void clearAll() {
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

      // Picture 리소스 해제 (메모리 누수 방지)
      picture.dispose();

      // 이전 캐시 정리
      _compositedCache?.dispose();

      _compositedCache = image;
      _compositedCacheKey = key;

      return image;
    } catch (e) {
      // 에러 시에도 Picture 해제
      picture.dispose();
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

  /// 가변 굵기 스트로크 그리기 (필압 + 틸트 적용)
  void _drawVariableWidthStroke(Canvas canvas, Stroke stroke, Paint basePaint) {
    for (int i = 0; i < stroke.points.length - 1; i++) {
      final p1 = stroke.points[i];
      final p2 = stroke.points[i + 1];

      final pressure = (p1.pressure + p2.pressure) / 2;
      final tilt = (p1.tilt + p2.tilt) / 2;

      // 필압 기반 굵기 (0.5 ~ 1.3 배율)
      double width = stroke.width * (0.5 + pressure * 0.8);

      // 틸트 적용: 기울일수록 굵어짐 (최대 1.5배)
      // tilt 0 = 수직, tilt 1 = 완전히 눕힘
      if (tilt > 0.1) {
        final tiltMultiplier = 1.0 + (tilt * 0.5); // 1.0 ~ 1.5
        width *= tiltMultiplier;
      }

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

/// 타일 기반 캐시 (대형 캔버스용) - LRU 캐시 적용
class TileCache {
  static const double tileSize = 512.0;
  static const int maxTiles = 100; // 최대 타일 수 (약 100MB 메모리 제한)

  final Map<String, ui.Image> _tiles = {};
  final List<String> _accessOrder = []; // LRU 순서 추적

  /// 타일 키 생성
  String _tileKey(int tileX, int tileY) => 'tile_${tileX}_$tileY';

  /// 타일 개수
  int get tileCount => _tiles.length;

  /// 타일 가져오기 (LRU 순서 업데이트)
  ui.Image? getTile(int tileX, int tileY) {
    final key = _tileKey(tileX, tileY);
    final tile = _tiles[key];

    if (tile != null) {
      // LRU 순서 업데이트: 접근한 타일을 맨 뒤로 이동
      _accessOrder.remove(key);
      _accessOrder.add(key);
    }

    return tile;
  }

  /// 타일 저장 (LRU 캐시 제한 적용)
  void setTile(int tileX, int tileY, ui.Image image) {
    final key = _tileKey(tileX, tileY);

    // 기존 타일 정리
    if (_tiles.containsKey(key)) {
      _tiles[key]?.dispose();
      _accessOrder.remove(key);
    }

    // LRU 캐시 제한: 최대 개수 초과 시 가장 오래된 타일 제거
    while (_tiles.length >= maxTiles) {
      _evictOldestTile();
    }

    _tiles[key] = image;
    _accessOrder.add(key);
  }

  /// 가장 오래된 타일 제거 (LRU)
  void _evictOldestTile() {
    if (_accessOrder.isEmpty) return;

    final oldestKey = _accessOrder.removeAt(0);
    final oldTile = _tiles.remove(oldestKey);
    oldTile?.dispose();
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
        _accessOrder.remove(key);
      }
    }
  }

  /// 전체 클리어
  void clear() {
    for (final tile in _tiles.values) {
      tile.dispose();
    }
    _tiles.clear();
    _accessOrder.clear();
  }
}
