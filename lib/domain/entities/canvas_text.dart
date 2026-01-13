import 'dart:ui';

/// Text box element that can be placed on the canvas
class CanvasText {
  final String id;
  final String text;
  final Offset position; // Top-left position on canvas
  final double fontSize;
  final Color color;
  final bool isBold;
  final bool isItalic;
  final int timestamp;

  CanvasText({
    required this.id,
    required this.text,
    required this.position,
    this.fontSize = 16.0,
    this.color = const Color(0xFF000000),
    this.isBold = false,
    this.isItalic = false,
    required this.timestamp,
  });

  CanvasText copyWith({
    String? id,
    String? text,
    Offset? position,
    double? fontSize,
    Color? color,
    bool? isBold,
    bool? isItalic,
    int? timestamp,
  }) {
    return CanvasText(
      id: id ?? this.id,
      text: text ?? this.text,
      position: position ?? this.position,
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'positionX': position.dx,
      'positionY': position.dy,
      'fontSize': fontSize,
      'color': color.value,
      'isBold': isBold,
      'isItalic': isItalic,
      'timestamp': timestamp,
    };
  }

  factory CanvasText.fromJson(Map<String, dynamic> json) {
    return CanvasText(
      id: json['id'] as String,
      text: json['text'] as String,
      position: Offset(
        (json['positionX'] as num).toDouble(),
        (json['positionY'] as num).toDouble(),
      ),
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 16.0,
      color: Color(json['color'] as int? ?? 0xFF000000),
      isBold: json['isBold'] as bool? ?? false,
      isItalic: json['isItalic'] as bool? ?? false,
      timestamp: json['timestamp'] as int,
    );
  }

  @override
  String toString() => 'CanvasText(id: $id, text: "$text", position: $position)';
}
