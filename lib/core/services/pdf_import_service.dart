import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/note_storage_service.dart';
import '../../domain/entities/canvas_shape.dart';

/// PDF 페이지 정보
class PdfPageInfo {
  final int pageNumber;
  final String imagePath;
  final double width;
  final double height;

  PdfPageInfo({
    required this.pageNumber,
    required this.imagePath,
    required this.width,
    required this.height,
  });
}

/// PDF 가져오기 서비스
class PdfImportService {
  static PdfImportService? _instance;
  static PdfImportService get instance {
    _instance ??= PdfImportService._();
    return _instance!;
  }

  PdfImportService._();

  String? _pdfCacheDirectory;

  /// PDF 캐시 디렉토리 가져오기
  Future<String> get pdfCacheDirectory async {
    if (_pdfCacheDirectory != null) return _pdfCacheDirectory!;

    final appDir = await getApplicationDocumentsDirectory();
    _pdfCacheDirectory =
        '${appDir.path}${Platform.pathSeparator}Winote${Platform.pathSeparator}pdf_cache';

    final dir = Directory(_pdfCacheDirectory!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return _pdfCacheDirectory!;
  }

  /// 파일 선택기로 PDF 파일 선택
  Future<String?> pickPdfFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: false,
        withReadStream: false,
      );

      if (result != null && result.files.isNotEmpty) {
        return result.files.first.path;
      }
      return null;
    } catch (e) {
      debugPrint('[PdfImportService] Error picking PDF: $e');
      return null;
    }
  }

  /// PDF 파일을 노트로 변환 (각 페이지를 배경 이미지로)
  Future<Note?> importPdfAsNote({
    required String pdfPath,
    String? title,
  }) async {
    try {
      final pdfFile = File(pdfPath);
      if (!await pdfFile.exists()) {
        debugPrint('[PdfImportService] PDF file not found: $pdfPath');
        return null;
      }

      // PDF 파일명에서 제목 추출
      final fileName = pdfPath.split(Platform.pathSeparator).last;
      final noteTitle = title ?? fileName.replaceAll('.pdf', '');

      // 새 노트 생성
      final now = DateTime.now();
      final noteId = now.millisecondsSinceEpoch.toString();

      // PDF 파일을 노트 이미지 폴더에 복사
      final cacheDir = await pdfCacheDirectory;
      final pdfCopyPath = '$cacheDir${Platform.pathSeparator}$noteId.pdf';
      await pdfFile.copy(pdfCopyPath);

      // 노트 생성 (PDF 경로를 메타데이터로 저장)
      final note = Note(
        id: noteId,
        title: noteTitle,
        pages: [
          NotePage(
            pageNumber: 0,
            strokes: [],
            shapes: [
              // PDF 배경 이미지로 저장 (CanvasShape 활용)
              CanvasShape.pdfBackground(
                id: 'pdf_bg_0',
                pdfPath: pdfCopyPath,
                pdfPageIndex: 0,
                position: Offset.zero,
                width: 800,
                height: 1131, // A4 비율
              ),
            ],
          ),
        ],
        createdAt: now,
        modifiedAt: now,
        tags: ['pdf', 'imported'],
      );

      return note;
    } catch (e) {
      debugPrint('[PdfImportService] Error importing PDF: $e');
      return null;
    }
  }

  /// PDF 페이지 수 가져오기 (간단한 방식)
  Future<int> getPdfPageCount(String pdfPath) async {
    try {
      // PDF 바이너리 분석으로 페이지 수 추정
      final file = File(pdfPath);
      final bytes = await file.readAsBytes();
      final content = String.fromCharCodes(bytes);

      // /Type /Page 패턴 찾기
      final pagePattern = RegExp(r'/Type\s*/Page[^s]');
      final matches = pagePattern.allMatches(content);

      return matches.isNotEmpty ? matches.length : 1;
    } catch (e) {
      debugPrint('[PdfImportService] Error getting page count: $e');
      return 1;
    }
  }

  /// PDF 파일로 다중 페이지 노트 생성
  Future<Note?> importPdfWithMultiplePages({
    required String pdfPath,
    String? title,
    int? pageCount,
  }) async {
    try {
      final pdfFile = File(pdfPath);
      if (!await pdfFile.exists()) {
        return null;
      }

      final fileName = pdfPath.split(Platform.pathSeparator).last;
      final noteTitle = title ?? fileName.replaceAll('.pdf', '');

      // PDF 페이지 수 가져오기
      final totalPages = pageCount ?? await getPdfPageCount(pdfPath);

      // 새 노트 생성
      final now = DateTime.now();
      final noteId = now.millisecondsSinceEpoch.toString();

      // PDF 파일 복사
      final cacheDir = await pdfCacheDirectory;
      final pdfCopyPath = '$cacheDir${Platform.pathSeparator}$noteId.pdf';
      await pdfFile.copy(pdfCopyPath);

      // 각 페이지를 NotePage로 생성
      final pages = <NotePage>[];
      for (int i = 0; i < totalPages; i++) {
        pages.add(NotePage(
          pageNumber: i,
          strokes: [],
          shapes: [
            CanvasShape.pdfBackground(
              id: 'pdf_bg_$i',
              pdfPath: pdfCopyPath,
              pdfPageIndex: i,
              position: Offset.zero,
              width: 800,
              height: 1131,
            ),
          ],
        ),);
      }

      final note = Note(
        id: noteId,
        title: noteTitle,
        pages: pages,
        createdAt: now,
        modifiedAt: now,
        tags: ['pdf', 'imported'],
      );

      return note;
    } catch (e) {
      debugPrint('[PdfImportService] Error: $e');
      return null;
    }
  }

  /// 특정 노트의 PDF 캐시 파일 삭제
  Future<void> deletePdfForNote(String noteId) async {
    try {
      final cacheDir = await pdfCacheDirectory;
      final pdfFile = File('$cacheDir${Platform.pathSeparator}$noteId.pdf');

      if (await pdfFile.exists()) {
        await pdfFile.delete();
        debugPrint('[PdfImportService] PDF cache deleted for note: $noteId');
      }
    } catch (e) {
      debugPrint('[PdfImportService] Error deleting PDF for note $noteId: $e');
    }
  }

  /// 캐시 정리
  Future<void> clearCache() async {
    try {
      final cacheDir = Directory(await pdfCacheDirectory);
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        await cacheDir.create();
      }
    } catch (e) {
      debugPrint('[PdfImportService] Error clearing cache: $e');
    }
  }
}
