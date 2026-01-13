import 'dart:ui';

/// Image element that can be placed on the canvas
class CanvasImage {
  final String id;
  final String imagePath; // Local file path to the image
  final Offset position; // Top-left position on canvas
  final Size size; // Display size
  final double rotation; // Rotation angle in radians
  final int timestamp;

  CanvasImage({
    required this.id,
    required this.imagePath,
    required this.position,
    required this.size,
    this.rotation = 0.0,
    required this.timestamp,
  });

  CanvasImage copyWith({
    String? id,
    String? imagePath,
    Offset? position,
    Size? size,
    double? rotation,
    int? timestamp,
  }) {
    return CanvasImage(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      position: position ?? this.position,
      size: size ?? this.size,
      rotation: rotation ?? this.rotation,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Get bounding rectangle
  Rect get bounds => Rect.fromLTWH(position.dx, position.dy, size.width, size.height);

  /// Check if a point is inside this image
  bool containsPoint(Offset point) {
    return bounds.contains(point);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imagePath': imagePath,
      'positionX': position.dx,
      'positionY': position.dy,
      'width': size.width,
      'height': size.height,
      'rotation': rotation,
      'timestamp': timestamp,
    };
  }

  factory CanvasImage.fromJson(Map<String, dynamic> json) {
    return CanvasImage(
      id: json['id'] as String,
      imagePath: json['imagePath'] as String,
      position: Offset(
        (json['positionX'] as num).toDouble(),
        (json['positionY'] as num).toDouble(),
      ),
      size: Size(
        (json['width'] as num).toDouble(),
        (json['height'] as num).toDouble(),
      ),
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      timestamp: json['timestamp'] as int,
    );
  }

  @override
  String toString() => 'CanvasImage(id: $id, position: $position, size: $size)';
}
