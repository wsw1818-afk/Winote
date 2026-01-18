import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/stroke.dart';

/// OCR 인식 결과
class OcrResult {
  final String text;
  final double confidence;
  final Rect boundingBox;

  OcrResult({
    required this.text,
    required this.confidence,
    required this.boundingBox,
  });
}

/// 손글씨 인식 서비스
/// 스트로크를 이미지로 렌더링하고 OCR을 수행합니다.
class OcrService {
  static OcrService? _instance;
  static OcrService get instance {
    _instance ??= OcrService._();
    return _instance!;
  }

  OcrService._();

  bool _isInitialized = false;
  bool _isProcessing = false;

  bool get isInitialized => _isInitialized;
  bool get isProcessing => _isProcessing;

  /// 서비스 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;

    // TODO: OCR 엔진 초기화 (예: Google ML Kit, Tesseract)
    // 현재는 placeholder 구현

    _isInitialized = true;
    debugPrint('[OCR] Service initialized');
  }

  /// 스트로크를 이미지로 렌더링
  Future<ui.Image?> renderStrokesToImage(
    List<Stroke> strokes, {
    double width = 1000,
    double height = 1000,
    Color backgroundColor = Colors.white,
  }) async {
    if (strokes.isEmpty) return null;

    // 바운딩 박스 계산
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

    // 패딩 추가
    const padding = 20.0;
    minX -= padding;
    minY -= padding;
    maxX += padding;
    maxY += padding;

    final contentWidth = maxX - minX;
    final contentHeight = maxY - minY;

    if (contentWidth <= 0 || contentHeight <= 0) return null;

    // 스케일 계산
    final scaleX = width / contentWidth;
    final scaleY = height / contentHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);

    // 배경 그리기
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = backgroundColor,
    );

    // 스트로크 그리기
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;

      final paint = Paint()
        ..color = Colors.black // OCR을 위해 검정색 사용
        ..strokeWidth = stroke.width * scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (stroke.points.length == 1) {
        final p = stroke.points.first;
        canvas.drawCircle(
          Offset((p.x - minX) * scale, (p.y - minY) * scale),
          paint.strokeWidth / 2,
          paint,
        );
      } else {
        final path = Path();
        final first = stroke.points.first;
        path.moveTo((first.x - minX) * scale, (first.y - minY) * scale);

        for (int i = 1; i < stroke.points.length; i++) {
          final p = stroke.points[i];
          path.lineTo((p.x - minX) * scale, (p.y - minY) * scale);
        }

        canvas.drawPath(path, paint);
      }
    }

    final picture = pictureRecorder.endRecording();
    return picture.toImage(width.toInt(), height.toInt());
  }

  /// 스트로크에서 텍스트 인식
  Future<List<OcrResult>> recognizeText(List<Stroke> strokes) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_isProcessing || strokes.isEmpty) {
      return [];
    }

    _isProcessing = true;

    try {
      // 이미지로 렌더링
      final image = await renderStrokesToImage(strokes);
      if (image == null) {
        return [];
      }

      // TODO: 실제 OCR 엔진 호출
      // 현재는 placeholder로 빈 결과 반환
      //
      // 실제 구현 시:
      // 1. Google ML Kit Text Recognition 사용
      // 2. 또는 Tesseract OCR 사용
      // 3. 또는 Windows OCR API 사용 (Platform Channel)

      debugPrint('[OCR] Processing ${strokes.length} strokes...');

      // Placeholder: 실제 OCR 결과 대신 안내 메시지
      return [
        OcrResult(
          text: '(OCR 기능은 향후 업데이트에서 지원 예정입니다)',
          confidence: 0.0,
          boundingBox: Rect.zero,
        ),
      ];
    } catch (e) {
      debugPrint('[OCR] Error: $e');
      return [];
    } finally {
      _isProcessing = false;
    }
  }

  /// 선택된 영역에서 텍스트 인식
  Future<String?> recognizeTextInRect(
    List<Stroke> strokes,
    Rect selectionRect,
  ) async {
    // 선택 영역 내의 스트로크만 필터링
    final selectedStrokes = strokes.where((stroke) {
      for (final point in stroke.points) {
        if (selectionRect.contains(Offset(point.x, point.y))) {
          return true;
        }
      }
      return false;
    }).toList();

    if (selectedStrokes.isEmpty) {
      return null;
    }

    final results = await recognizeText(selectedStrokes);
    if (results.isEmpty) {
      return null;
    }

    return results.map((r) => r.text).join('\n');
  }

  /// 이미지 파일로 저장 (디버깅/테스트용)
  Future<String?> saveStrokesAsImage(
    List<Stroke> strokes, {
    String? fileName,
  }) async {
    final image = await renderStrokesToImage(strokes);
    if (image == null) return null;

    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final bytes = byteData.buffer.asUint8List();

      final appDir = await getApplicationDocumentsDirectory();
      final ocrDir = Directory('${appDir.path}${Platform.pathSeparator}Winote${Platform.pathSeparator}ocr_temp');
      if (!await ocrDir.exists()) {
        await ocrDir.create(recursive: true);
      }

      final name = fileName ?? 'ocr_${DateTime.now().millisecondsSinceEpoch}';
      final filePath = '${ocrDir.path}${Platform.pathSeparator}$name.png';

      final file = File(filePath);
      await file.writeAsBytes(bytes);

      debugPrint('[OCR] Saved image: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('[OCR] Error saving image: $e');
      return null;
    }
  }

  /// 임시 파일 정리
  Future<void> clearTempFiles() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final ocrDir = Directory('${appDir.path}${Platform.pathSeparator}Winote${Platform.pathSeparator}ocr_temp');
      if (await ocrDir.exists()) {
        await ocrDir.delete(recursive: true);
        debugPrint('[OCR] Cleared temp files');
      }
    } catch (e) {
      debugPrint('[OCR] Error clearing temp files: $e');
    }
  }
}

/// OCR 상태 위젯 (UI에서 사용)
class OcrStatusWidget extends StatelessWidget {
  final bool isProcessing;
  final String? result;

  const OcrStatusWidget({
    super.key,
    required this.isProcessing,
    this.result,
  });

  @override
  Widget build(BuildContext context) {
    if (isProcessing) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('텍스트 인식 중...'),
        ],
      );
    }

    if (result != null && result!.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              children: [
                Icon(Icons.text_fields, size: 16),
                SizedBox(width: 4),
                Text(
                  '인식된 텍스트',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              result!,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
