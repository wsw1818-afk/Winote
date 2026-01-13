import 'dart:ui';

/// 스트로크의 경계 상자
class BoundingBox {
  double minX;
  double minY;
  double maxX;
  double maxY;

  BoundingBox({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });

  /// 빈 BoundingBox 생성
  factory BoundingBox.empty() {
    return BoundingBox(
      minX: double.infinity,
      minY: double.infinity,
      maxX: double.negativeInfinity,
      maxY: double.negativeInfinity,
    );
  }

  /// 초기 포인트로 BoundingBox 생성
  factory BoundingBox.fromPoint(double x, double y) {
    return BoundingBox(minX: x, minY: y, maxX: x, maxY: y);
  }

  /// Rect로 변환
  Rect toRect() => Rect.fromLTRB(minX, minY, maxX, maxY);

  /// 너비
  double get width => maxX - minX;

  /// 높이
  double get height => maxY - minY;

  /// 중심점
  Offset get center => Offset((minX + maxX) / 2, (minY + maxY) / 2);

  /// 포인트로 확장
  void expand(double x, double y) {
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
  }

  /// 다른 BoundingBox와 병합
  void merge(BoundingBox other) {
    if (other.minX < minX) minX = other.minX;
    if (other.minY < minY) minY = other.minY;
    if (other.maxX > maxX) maxX = other.maxX;
    if (other.maxY > maxY) maxY = other.maxY;
  }

  /// Rect와 겹치는지 확인
  bool overlaps(Rect rect) {
    return !(maxX < rect.left ||
        minX > rect.right ||
        maxY < rect.top ||
        minY > rect.bottom);
  }

  /// 포인트가 내부에 있는지 확인
  bool contains(double x, double y) {
    return x >= minX && x <= maxX && y >= minY && y <= maxY;
  }

  /// 복사본 생성
  BoundingBox copy() {
    return BoundingBox(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  @override
  String toString() =>
      'BoundingBox(minX: $minX, minY: $minY, maxX: $maxX, maxY: $maxY)';
}
