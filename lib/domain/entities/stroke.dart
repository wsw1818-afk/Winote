import 'dart:ui';

import 'stroke_point.dart';
import 'bounding_box.dart';

/// 필기 도구 타입
enum ToolType {
  pen,        // 기본 펜
  pencil,     // 연필
  marker,     // 마커
  highlighter, // 형광펜
  eraser,     // 지우개
}

/// 스트로크 (펜 획)
class Stroke {
  final String id;
  final ToolType toolType;
  final Color color;
  final double width;
  final List<StrokePoint> points;
  BoundingBox boundingBox;
  final int timestamp;

  Stroke({
    required this.id,
    required this.toolType,
    required this.color,
    required this.width,
    required this.points,
    BoundingBox? boundingBox,
    required this.timestamp,
  }) : boundingBox = boundingBox ?? _calculateBoundingBox(points);

  static BoundingBox _calculateBoundingBox(List<StrokePoint> points) {
    if (points.isEmpty) return BoundingBox.empty();
    final bbox = BoundingBox.fromPoint(points.first.x, points.first.y);
    for (int i = 1; i < points.length; i++) {
      bbox.expand(points[i].x, points[i].y);
    }
    return bbox;
  }

  /// 새 스트로크 생성 (시작점 포함)
  factory Stroke.create({
    required String id,
    required ToolType toolType,
    required Color color,
    required double width,
    required StrokePoint startPoint,
  }) {
    return Stroke(
      id: id,
      toolType: toolType,
      color: color,
      width: width,
      points: [startPoint],
      boundingBox: BoundingBox.fromPoint(startPoint.x, startPoint.y),
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 포인트 추가
  void addPoint(StrokePoint point) {
    points.add(point);
    boundingBox.expand(point.x, point.y);
  }

  /// BoundingBox 재계산
  void recalculateBoundingBox() {
    if (points.isEmpty) {
      boundingBox = BoundingBox.empty();
      return;
    }

    boundingBox = BoundingBox.fromPoint(points.first.x, points.first.y);
    for (int i = 1; i < points.length; i++) {
      boundingBox.expand(points[i].x, points[i].y);
    }
  }

  /// 압력에 따른 실제 굵기 계산
  double getWidthAtPressure(double pressure) {
    // 압력 범위: 0.0 ~ 1.0
    // 굵기 배율: 0.5x ~ 2.0x
    final multiplier = 0.5 + pressure * 1.5;
    return width * multiplier;
  }

  /// 복사본 생성
  Stroke copyWith({
    String? id,
    ToolType? toolType,
    Color? color,
    double? width,
    List<StrokePoint>? points,
    BoundingBox? boundingBox,
    int? timestamp,
  }) {
    return Stroke(
      id: id ?? this.id,
      toolType: toolType ?? this.toolType,
      color: color ?? this.color,
      width: width ?? this.width,
      points: points ?? List.from(this.points),
      boundingBox: boundingBox ?? this.boundingBox.copy(),
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// 새 포인트를 추가한 복사본 생성 (불변 패턴)
  Stroke copyWithNewPoint(StrokePoint point) {
    final newPoints = List<StrokePoint>.from(points)..add(point);
    final newBoundingBox = boundingBox.copy()..expand(point.x, point.y);
    return Stroke(
      id: id,
      toolType: toolType,
      color: color,
      width: width,
      points: newPoints,
      boundingBox: newBoundingBox,
      timestamp: timestamp,
    );
  }

  @override
  String toString() =>
      'Stroke(id: $id, tool: $toolType, points: ${points.length})';
}
