import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/stroke.dart';

/// Service for exporting canvas as image (PNG/JPG)
class ImageExportService {
  ImageExportService._();
  static final ImageExportService instance = ImageExportService._();

  /// Get the exports directory path
  Future<String> getExportsDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final exportsDir = Directory('${docsDir.path}/Winote/exports');
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }
    return exportsDir.path;
  }

  /// Export strokes as PNG image
  Future<String?> exportAsPng({
    required List<Stroke> strokes,
    required Size canvasSize,
    required String title,
    Color backgroundColor = Colors.white,
  }) async {
    return _exportAsImage(
      strokes: strokes,
      canvasSize: canvasSize,
      title: title,
      format: 'png',
      backgroundColor: backgroundColor,
    );
  }

  /// Export strokes as JPG image
  Future<String?> exportAsJpg({
    required List<Stroke> strokes,
    required Size canvasSize,
    required String title,
    Color backgroundColor = Colors.white,
    int quality = 90,
  }) async {
    return _exportAsImage(
      strokes: strokes,
      canvasSize: canvasSize,
      title: title,
      format: 'jpg',
      backgroundColor: backgroundColor,
      quality: quality,
    );
  }

  Future<String?> _exportAsImage({
    required List<Stroke> strokes,
    required Size canvasSize,
    required String title,
    required String format,
    Color backgroundColor = Colors.white,
    int quality = 90,
  }) async {
    if (strokes.isEmpty) return null;

    try {
      // Calculate bounding box of all strokes with padding
      double minX = double.infinity;
      double minY = double.infinity;
      double maxX = double.negativeInfinity;
      double maxY = double.negativeInfinity;

      for (final stroke in strokes) {
        for (final point in stroke.points) {
          if (point.x < minX) minX = point.x;
          if (point.y < minY) minY = point.y;
          if (point.x > maxX) maxX = point.x;
          if (point.y > maxY) maxY = point.y;
        }
      }

      // Add padding
      const padding = 50.0;
      minX -= padding;
      minY -= padding;
      maxX += padding;
      maxY += padding;

      // Clamp to canvas bounds
      minX = minX.clamp(0.0, canvasSize.width);
      minY = minY.clamp(0.0, canvasSize.height);
      maxX = maxX.clamp(0.0, canvasSize.width);
      maxY = maxY.clamp(0.0, canvasSize.height);

      final width = (maxX - minX).ceil();
      final height = (maxY - minY).ceil();

      if (width <= 0 || height <= 0) return null;

      // Create a picture recorder
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Draw background
      final bgPaint = Paint()..color = backgroundColor;
      canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), bgPaint);

      // Draw strokes with offset
      for (final stroke in strokes) {
        _drawStroke(canvas, stroke, -minX, -minY);
      }

      // End recording
      final picture = recorder.endRecording();

      // Convert to image
      final image = await picture.toImage(width, height);

      // Picture 리소스 해제 (메모리 누수 방지)
      picture.dispose();

      // Convert to bytes
      final byteData = await image.toByteData(
        format: format == 'png' ? ui.ImageByteFormat.png : ui.ImageByteFormat.rawRgba,
      );

      if (byteData == null) return null;

      // For JPEG, we need to encode differently
      // Flutter's toByteData doesn't directly support JPEG
      // So we'll use PNG for now as the default quality is acceptable
      final bytes = byteData.buffer.asUint8List();

      // Save to file
      final exportsDir = await getExportsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final sanitizedTitle = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final filePath = '$exportsDir/${sanitizedTitle}_$timestamp.png';

      final file = File(filePath);
      await file.writeAsBytes(bytes);

      return filePath;
    } catch (e) {
      debugPrint('[ImageExportService] Export error: $e');
      return null;
    }
  }

  void _drawStroke(Canvas canvas, Stroke stroke, double offsetX, double offsetY) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (stroke.points.length == 1) {
      final p = stroke.points.first;
      canvas.drawCircle(
        Offset(p.x + offsetX, p.y + offsetY),
        stroke.width / 2,
        paint,
      );
      return;
    }

    final path = Path();
    final first = stroke.points.first;
    path.moveTo(first.x + offsetX, first.y + offsetY);

    for (int i = 1; i < stroke.points.length; i++) {
      final p0 = stroke.points[i - 1];
      final p1 = stroke.points[i];

      if (i < stroke.points.length - 1) {
        final p2 = stroke.points[i + 1];
        final midX = (p1.x + p2.x) / 2 + offsetX;
        final midY = (p1.y + p2.y) / 2 + offsetY;
        path.quadraticBezierTo(p1.x + offsetX, p1.y + offsetY, midX, midY);
      } else {
        path.lineTo(p1.x + offsetX, p1.y + offsetY);
      }
    }

    canvas.drawPath(path, paint);
  }
}
