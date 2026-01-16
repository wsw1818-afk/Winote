import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../domain/entities/stroke.dart';
import '../../domain/entities/stroke_point.dart';

/// PDF Export Service
/// Exports canvas strokes to PDF format
class PdfExportService {
  PdfExportService._();
  static final PdfExportService instance = PdfExportService._();

  /// Export strokes to PDF file
  /// Returns the file path of the exported PDF
  Future<String?> exportToPdf({
    required List<Stroke> strokes,
    required String title,
    Size canvasSize = const Size(800, 600),
  }) async {
    try {
      // Create PDF document
      final PdfDocument document = PdfDocument();

      // Set PDF page size (A4)
      final PdfPage page = document.pages.add();
      final Size pageSize = Size(
        page.getClientSize().width,
        page.getClientSize().height,
      );

      // Calculate scale to fit canvas to page
      final double scaleX = pageSize.width / canvasSize.width;
      final double scaleY = pageSize.height / canvasSize.height;
      final double scale = scaleX < scaleY ? scaleX : scaleY;

      // Draw strokes on PDF
      final PdfGraphics graphics = page.graphics;

      for (final stroke in strokes) {
        if (stroke.points.length < 2) continue;

        // Create pen with stroke color and width
        final PdfPen pen = PdfPen(
          PdfColor(
            stroke.color.red,
            stroke.color.green,
            stroke.color.blue,
            stroke.color.alpha,
          ),
          width: stroke.width * scale,
        );

        // Draw lines between points
        for (int i = 0; i < stroke.points.length - 1; i++) {
          final point1 = stroke.points[i];
          final point2 = stroke.points[i + 1];

          graphics.drawLine(
            pen,
            Offset(point1.x * scale, point1.y * scale),
            Offset(point2.x * scale, point2.y * scale),
          );
        }
      }

      // Save PDF to file
      final directory = await getApplicationDocumentsDirectory();
      final pdfDir = Directory('${directory.path}/Winote/exports');
      if (!await pdfDir.exists()) {
        await pdfDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${_sanitizeFileName(title)}_$timestamp.pdf';
      final filePath = '${pdfDir.path}/$fileName';

      final File file = File(filePath);
      await file.writeAsBytes(await document.save());

      // Dispose document
      document.dispose();

      return filePath;
    } catch (e) {
      debugPrint('PDF export error: $e');
      return null;
    }
  }

  /// Export strokes to PDF with smooth Catmull-Rom spline rendering
  Future<String?> exportToPdfSmooth({
    required List<Stroke> strokes,
    required String title,
    Size canvasSize = const Size(800, 600),
  }) async {
    try {
      final PdfDocument document = PdfDocument();
      final PdfPage page = document.pages.add();
      final Size pageSize = Size(
        page.getClientSize().width,
        page.getClientSize().height,
      );

      // 실제 스트로크들의 바운딩 박스 계산
      final bounds = _calculateStrokesBounds(strokes);

      // 스트로크가 없거나 바운딩 박스가 없으면 빈 PDF 반환
      if (bounds == null) {
        final directory = await getApplicationDocumentsDirectory();
        final pdfDir = Directory('${directory.path}/Winote/exports');
        if (!await pdfDir.exists()) {
          await pdfDir.create(recursive: true);
        }
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = '${_sanitizeFileName(title)}_$timestamp.pdf';
        final filePath = '${pdfDir.path}/$fileName';
        final File file = File(filePath);
        await file.writeAsBytes(await document.save());
        document.dispose();
        return filePath;
      }

      // 여백 추가
      const double margin = 20.0;
      final contentWidth = bounds.width + margin * 2;
      final contentHeight = bounds.height + margin * 2;

      // 페이지에 맞게 스케일 계산
      final double scaleX = pageSize.width / contentWidth;
      final double scaleY = pageSize.height / contentHeight;
      final double scale = scaleX < scaleY ? scaleX : scaleY;

      // 오프셋 계산 (스트로크를 원점으로 이동 + 여백)
      final double offsetX = -bounds.left + margin;
      final double offsetY = -bounds.top + margin;

      final PdfGraphics graphics = page.graphics;

      for (final stroke in strokes) {
        if (stroke.points.length < 2) continue;

        // 색상 알파값 확인 및 보정
        final int alpha = stroke.color.alpha > 0 ? stroke.color.alpha : 255;

        final PdfPen pen = PdfPen(
          PdfColor(
            stroke.color.red,
            stroke.color.green,
            stroke.color.blue,
            alpha,
          ),
          width: stroke.width * scale,
        );

        // Generate smooth path using Catmull-Rom spline with offset
        final smoothPoints = _generateCatmullRomPointsWithOffset(
          stroke.points,
          scale,
          offsetX,
          offsetY,
        );

        for (int i = 0; i < smoothPoints.length - 1; i++) {
          graphics.drawLine(
            pen,
            smoothPoints[i],
            smoothPoints[i + 1],
          );
        }
      }

      final directory = await getApplicationDocumentsDirectory();
      final pdfDir = Directory('${directory.path}/Winote/exports');
      if (!await pdfDir.exists()) {
        await pdfDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${_sanitizeFileName(title)}_$timestamp.pdf';
      final filePath = '${pdfDir.path}/$fileName';

      final File file = File(filePath);
      await file.writeAsBytes(await document.save());
      document.dispose();

      return filePath;
    } catch (e) {
      debugPrint('PDF export error: $e');
      return null;
    }
  }

  /// Calculate bounding box of all strokes
  Rect? _calculateStrokesBounds(List<Stroke> strokes) {
    if (strokes.isEmpty) return null;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    bool hasPoints = false;

    for (final stroke in strokes) {
      for (final point in stroke.points) {
        hasPoints = true;
        if (point.x < minX) minX = point.x;
        if (point.y < minY) minY = point.y;
        if (point.x > maxX) maxX = point.x;
        if (point.y > maxY) maxY = point.y;
      }
    }

    if (!hasPoints) return null;

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Generate Catmull-Rom spline points with offset for PDF coordinate transform
  List<Offset> _generateCatmullRomPointsWithOffset(
    List<StrokePoint> points,
    double scale,
    double offsetX,
    double offsetY,
  ) {
    if (points.length < 2) return [];
    if (points.length == 2) {
      return [
        Offset((points[0].x + offsetX) * scale, (points[0].y + offsetY) * scale),
        Offset((points[1].x + offsetX) * scale, (points[1].y + offsetY) * scale),
      ];
    }

    final List<Offset> result = [];
    const int segments = 8;

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : points[i + 1];

      for (int j = 0; j <= segments; j++) {
        final t = j / segments;
        final point = _catmullRom(
          Offset(p0.x + offsetX, p0.y + offsetY),
          Offset(p1.x + offsetX, p1.y + offsetY),
          Offset(p2.x + offsetX, p2.y + offsetY),
          Offset(p3.x + offsetX, p3.y + offsetY),
          t,
        );
        result.add(Offset(point.dx * scale, point.dy * scale));
      }
    }

    return result;
  }

  /// Generate Catmull-Rom spline points for smooth curves
  List<Offset> _generateCatmullRomPoints(List<StrokePoint> points, double scale) {
    if (points.length < 2) return [];
    if (points.length == 2) {
      return [
        Offset(points[0].x * scale, points[0].y * scale),
        Offset(points[1].x * scale, points[1].y * scale),
      ];
    }

    final List<Offset> result = [];
    const int segments = 8;

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : points[i + 1];

      for (int j = 0; j <= segments; j++) {
        final t = j / segments;
        final point = _catmullRom(
          Offset(p0.x, p0.y),
          Offset(p1.x, p1.y),
          Offset(p2.x, p2.y),
          Offset(p3.x, p3.y),
          t,
        );
        result.add(Offset(point.dx * scale, point.dy * scale));
      }
    }

    return result;
  }

  /// Catmull-Rom interpolation
  Offset _catmullRom(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    final t2 = t * t;
    final t3 = t2 * t;

    return Offset(
      0.5 * ((2 * p1.dx) +
          (-p0.dx + p2.dx) * t +
          (2 * p0.dx - 5 * p1.dx + 4 * p2.dx - p3.dx) * t2 +
          (-p0.dx + 3 * p1.dx - 3 * p2.dx + p3.dx) * t3),
      0.5 * ((2 * p1.dy) +
          (-p0.dy + p2.dy) * t +
          (2 * p0.dy - 5 * p1.dy + 4 * p2.dy - p3.dy) * t2 +
          (-p0.dy + 3 * p1.dy - 3 * p2.dy + p3.dy) * t3),
    );
  }

  /// Sanitize filename
  String _sanitizeFileName(String name) {
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
  }

  /// Get exports directory path
  Future<String> getExportsDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final pdfDir = Directory('${directory.path}/Winote/exports');
    if (!await pdfDir.exists()) {
      await pdfDir.create(recursive: true);
    }
    return pdfDir.path;
  }

  /// List all exported PDFs
  Future<List<File>> listExportedPdfs() async {
    final dirPath = await getExportsDirectory();
    final dir = Directory(dirPath);
    final files = await dir.list().toList();
    return files
        .whereType<File>()
        .where((f) => f.path.endsWith('.pdf'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
  }
}
