import 'dart:ui';

/// Shape types that can be drawn on canvas (editable shapes)
enum CanvasShapeType {
  line,
  rectangle,
  circle,
  arrow,
}

/// Shape element that can be placed and edited on the canvas
class CanvasShape {
  final String id;
  final CanvasShapeType type;
  final Offset startPoint;
  final Offset endPoint;
  final Color color;
  final double strokeWidth;
  final bool isFilled;
  final int timestamp;

  CanvasShape({
    required this.id,
    required this.type,
    required this.startPoint,
    required this.endPoint,
    required this.color,
    this.strokeWidth = 2.0,
    this.isFilled = false,
    required this.timestamp,
  });

  CanvasShape copyWith({
    String? id,
    CanvasShapeType? type,
    Offset? startPoint,
    Offset? endPoint,
    Color? color,
    double? strokeWidth,
    bool? isFilled,
    int? timestamp,
  }) {
    return CanvasShape(
      id: id ?? this.id,
      type: type ?? this.type,
      startPoint: startPoint ?? this.startPoint,
      endPoint: endPoint ?? this.endPoint,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      isFilled: isFilled ?? this.isFilled,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Get bounding rectangle of the shape
  Rect get bounds {
    final left = startPoint.dx < endPoint.dx ? startPoint.dx : endPoint.dx;
    final top = startPoint.dy < endPoint.dy ? startPoint.dy : endPoint.dy;
    final right = startPoint.dx > endPoint.dx ? startPoint.dx : endPoint.dx;
    final bottom = startPoint.dy > endPoint.dy ? startPoint.dy : endPoint.dy;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Get center point of the shape
  Offset get center => Offset(
    (startPoint.dx + endPoint.dx) / 2,
    (startPoint.dy + endPoint.dy) / 2,
  );

  /// Check if a point is near this shape (for selection)
  bool containsPoint(Offset point, {double tolerance = 10.0}) {
    switch (type) {
      case CanvasShapeType.line:
      case CanvasShapeType.arrow:
        return _isPointNearLine(point, startPoint, endPoint, tolerance);
      case CanvasShapeType.rectangle:
        final rect = bounds.inflate(tolerance);
        if (!rect.contains(point)) return false;
        // Check if near edges (not inside if not filled)
        if (!isFilled) {
          final innerRect = bounds.deflate(tolerance);
          return !innerRect.contains(point);
        }
        return true;
      case CanvasShapeType.circle:
        final center = this.center;
        final radius = (endPoint - startPoint).distance / 2;
        final distance = (point - center).distance;
        if (isFilled) {
          return distance <= radius + tolerance;
        } else {
          return (distance - radius).abs() <= tolerance;
        }
    }
  }

  /// Check if point is near a line segment
  bool _isPointNearLine(Offset point, Offset lineStart, Offset lineEnd, double tolerance) {
    final dx = lineEnd.dx - lineStart.dx;
    final dy = lineEnd.dy - lineStart.dy;
    final lengthSq = dx * dx + dy * dy;

    if (lengthSq == 0) {
      return (point - lineStart).distance <= tolerance;
    }

    var t = ((point.dx - lineStart.dx) * dx + (point.dy - lineStart.dy) * dy) / lengthSq;
    t = t.clamp(0.0, 1.0);

    final projection = Offset(
      lineStart.dx + t * dx,
      lineStart.dy + t * dy,
    );

    return (point - projection).distance <= tolerance;
  }

  /// Get handle positions for editing
  List<Offset> get handles => [startPoint, endPoint];

  /// Get which handle (if any) is at the given point
  int? getHandleAt(Offset point, {double tolerance = 15.0}) {
    if ((point - startPoint).distance <= tolerance) return 0;
    if ((point - endPoint).distance <= tolerance) return 1;
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.index,
      'startX': startPoint.dx,
      'startY': startPoint.dy,
      'endX': endPoint.dx,
      'endY': endPoint.dy,
      'color': color.value,
      'strokeWidth': strokeWidth,
      'isFilled': isFilled,
      'timestamp': timestamp,
    };
  }

  factory CanvasShape.fromJson(Map<String, dynamic> json) {
    return CanvasShape(
      id: json['id'] as String,
      type: CanvasShapeType.values[json['type'] as int],
      startPoint: Offset(
        (json['startX'] as num).toDouble(),
        (json['startY'] as num).toDouble(),
      ),
      endPoint: Offset(
        (json['endX'] as num).toDouble(),
        (json['endY'] as num).toDouble(),
      ),
      color: Color(json['color'] as int),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2.0,
      isFilled: json['isFilled'] as bool? ?? false,
      timestamp: json['timestamp'] as int,
    );
  }

  @override
  String toString() => 'CanvasShape(id: $id, type: $type, start: $startPoint, end: $endPoint)';
}
