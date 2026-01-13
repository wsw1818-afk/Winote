import 'dart:typed_data';

/// 스트로크의 개별 포인트
class StrokePoint {
  final double x;
  final double y;
  final double pressure;
  final double tilt;
  final int timestamp;

  const StrokePoint({
    required this.x,
    required this.y,
    required this.pressure,
    required this.tilt,
    required this.timestamp,
  });

  /// 바이너리 직렬화 크기 (20 bytes)
  static const int binarySize = 20;

  /// 바이너리로 직렬화
  Uint8List toBytes() {
    final data = ByteData(binarySize);
    data.setFloat32(0, x, Endian.little);
    data.setFloat32(4, y, Endian.little);
    data.setFloat32(8, pressure, Endian.little);
    data.setFloat32(12, tilt, Endian.little);
    data.setInt32(16, timestamp, Endian.little);
    return data.buffer.asUint8List();
  }

  /// 바이너리에서 역직렬화
  factory StrokePoint.fromBytes(ByteData data, int offset) {
    return StrokePoint(
      x: data.getFloat32(offset, Endian.little),
      y: data.getFloat32(offset + 4, Endian.little),
      pressure: data.getFloat32(offset + 8, Endian.little),
      tilt: data.getFloat32(offset + 12, Endian.little),
      timestamp: data.getInt32(offset + 16, Endian.little),
    );
  }

  /// 복사본 생성
  StrokePoint copyWith({
    double? x,
    double? y,
    double? pressure,
    double? tilt,
    int? timestamp,
  }) {
    return StrokePoint(
      x: x ?? this.x,
      y: y ?? this.y,
      pressure: pressure ?? this.pressure,
      tilt: tilt ?? this.tilt,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  String toString() =>
      'StrokePoint(x: $x, y: $y, pressure: $pressure, tilt: $tilt)';
}
