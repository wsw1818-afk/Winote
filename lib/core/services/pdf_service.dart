import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../domain/entities/stroke.dart';
import '../../domain/entities/stroke_point.dart';
import 'note_storage_service.dart';

/// PDF 가져오기/내보내기 서비스
class PdfService {
  static final PdfService instance = PdfService._();
  PdfService._();

  /// PDF 파일 가져오기 (배경 이미지로 변환)
  /// 각 페이지를 이미지로 변환하여 노트 페이지 배경으로 사용
  Future<List<String>> importPdf(String pdfPath) async {
    final file = File(pdfPath);
    if (!await file.exists()) {
      throw Exception('PDF 파일을 찾을 수 없습니다: $pdfPath');
    }

    final bytes = await file.readAsBytes();
    final document = PdfDocument(inputBytes: bytes);

    final imagePaths = <String>[];
    final appDir = await getApplicationDocumentsDirectory();
    final pdfImagesDir = Directory('${appDir.path}/Winote/pdf_images');
    if (!await pdfImagesDir.exists()) {
      await pdfImagesDir.create(recursive: true);
    }

    // 각 페이지를 이미지로 추출
    for (int i = 0; i < document.pages.count; i++) {
      try {
        final page = document.pages[i];

        // 페이지를 이미지로 렌더링 (300 DPI)
        final image = await page.extractImages();
        if (image.isNotEmpty) {
          // 첫 번째 이미지 저장
          final imagePath = '${pdfImagesDir.path}/pdf_page_${DateTime.now().millisecondsSinceEpoch}_$i.png';
          final imageFile = File(imagePath);
          await imageFile.writeAsBytes(image.first.imageData);
          imagePaths.add(imagePath);
        }
      } catch (e) {
        // 페이지 추출 실패 시 빈 페이지로 처리
        debugPrint('PDF 페이지 $i 추출 실패: $e');
      }
    }

    document.dispose();
    return imagePaths;
  }

  /// 노트를 PDF로 내보내기
  Future<String> exportNoteToPdf(Note note, {int quality = 2}) async {
    final document = PdfDocument();

    // A4 크기 (595.28 x 841.89 points at 72 DPI)
    const pageWidth = 595.28;
    const pageHeight = 841.89;

    for (final notePage in note.pages) {
      // PDF 페이지 추가
      final page = document.pages.add();
      final graphics = page.graphics;

      // 배경 이미지가 있으면 그리기
      if (notePage.backgroundImagePath != null) {
        try {
          final imageFile = File(notePage.backgroundImagePath!);
          if (await imageFile.exists()) {
            final imageBytes = await imageFile.readAsBytes();
            final pdfImage = PdfBitmap(imageBytes);
            graphics.drawImage(
              pdfImage,
              Rect.fromLTWH(0, 0, pageWidth, pageHeight),
            );
          }
        } catch (e) {
          debugPrint('배경 이미지 로드 실패: $e');
        }
      }

      // 스트로크 그리기
      for (final stroke in notePage.strokes) {
        _drawStrokeToPdf(graphics, stroke, pageWidth, pageHeight);
      }
    }

    // 저장
    final appDir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${appDir.path}/Winote/exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    final fileName = '${note.title.replaceAll(RegExp(r'[^\w\s-]'), '')}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final filePath = '${exportDir.path}/$fileName';

    final bytes = await document.save();
    final file = File(filePath);
    await file.writeAsBytes(bytes);

    document.dispose();

    return filePath;
  }

  /// 현재 페이지만 PDF로 내보내기
  Future<String> exportPageToPdf(
    NotePage page,
    String noteTitle,
    Size canvasSize,
  ) async {
    final document = PdfDocument();

    // 캔버스 크기에 맞는 페이지 생성
    final pageWidth = canvasSize.width;
    final pageHeight = canvasSize.height;

    final pdfPage = document.pages.add();
    final graphics = pdfPage.graphics;

    // 스트로크 그리기
    for (final stroke in page.strokes) {
      _drawStrokeToPdf(graphics, stroke, pageWidth, pageHeight);
    }

    // 저장
    final appDir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${appDir.path}/Winote/exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    final fileName = '${noteTitle}_page${page.pageNumber + 1}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final filePath = '${exportDir.path}/$fileName';

    final bytes = await document.save();
    final file = File(filePath);
    await file.writeAsBytes(bytes);

    document.dispose();

    return filePath;
  }

  /// 캔버스를 이미지로 내보내기 (PNG)
  Future<String> exportCanvasToImage(
    ui.Image image,
    String noteTitle,
  ) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception('이미지 변환 실패');
    }

    final appDir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${appDir.path}/Winote/exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    final fileName = '${noteTitle.replaceAll(RegExp(r'[^\w\s-]'), '')}_${DateTime.now().millisecondsSinceEpoch}.png';
    final filePath = '${exportDir.path}/$fileName';

    final file = File(filePath);
    await file.writeAsBytes(byteData.buffer.asUint8List());

    return filePath;
  }

  /// 스트로크를 PDF에 그리기
  void _drawStrokeToPdf(
    PdfGraphics graphics,
    Stroke stroke,
    double pageWidth,
    double pageHeight,
  ) {
    if (stroke.points.length < 2) return;

    // 색상 변환
    final color = PdfColor(
      stroke.color.red,
      stroke.color.green,
      stroke.color.blue,
      stroke.color.alpha,
    );

    // 펜 생성
    final pen = PdfPen(
      color,
      width: stroke.width,
      lineCap: PdfLineCap.round,
      lineJoin: PdfLineJoin.round,
    );

    // 형광펜은 반투명 처리
    if (stroke.toolType == ToolType.highlighter) {
      pen.color = PdfColor(
        stroke.color.red,
        stroke.color.green,
        stroke.color.blue,
        (stroke.color.alpha * 0.4).round(),
      );
    }

    // 경로 그리기
    final path = PdfPath();
    path.startFigure();

    final firstPoint = stroke.points.first;
    path.addLine(
      Offset(firstPoint.x, firstPoint.y),
      Offset(stroke.points[1].x, stroke.points[1].y),
    );

    for (int i = 2; i < stroke.points.length; i++) {
      final p = stroke.points[i];
      final prev = stroke.points[i - 1];
      path.addLine(Offset(prev.x, prev.y), Offset(p.x, p.y));
    }

    graphics.drawPath(path, pen: pen);
  }

  /// 내보내기 폴더 경로 가져오기
  Future<String> getExportDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${appDir.path}/Winote/exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    return exportDir.path;
  }

  /// 내보낸 파일 목록 가져오기
  Future<List<FileSystemEntity>> getExportedFiles() async {
    final exportPath = await getExportDirectory();
    final exportDir = Directory(exportPath);
    return exportDir.listSync();
  }

  /// 내보낸 파일 삭제
  Future<void> deleteExportedFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
