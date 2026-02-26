import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../../../core/services/document_scanner_service.dart';
import 'scanner_page.dart';

/// 스캔 결과를 노트에 삽입하는 모드
enum ScanInsertMode {
  image, // 캔버스에 이미지로 삽입
  background, // 페이지 배경으로 설정
}

/// 스캔 결과 확인 + 새 노트 열기 페이지
class FilterPage extends StatefulWidget {
  final List<String> imagePaths;
  final ScanEntryMode entryMode;
  final void Function(String imagePath, ScanInsertMode mode)? onResult;

  const FilterPage({
    super.key,
    required this.imagePaths,
    this.entryMode = ScanEntryMode.standalone,
    this.onResult,
  });

  @override
  State<FilterPage> createState() => _FilterPageState();
}

class _FilterPageState extends State<FilterPage> {
  bool _isProcessing = false;

  String get _currentImagePath => widget.imagePaths.first;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        title: const Text('스캔 결과'),
      ),
      body: Column(
        children: [
          // 이미지 미리보기
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Image.file(
                      File(_currentImagePath),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                if (_isProcessing)
                  Container(
                    color: Colors.black38,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          // 새 노트로 필기 시작 버튼
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SafeArea(
              child: Column(
                children: [
                  // 메인 버튼: 새 노트로 필기 시작
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _openAsNewNote,
                      icon: const Icon(Icons.edit_note, size: 24),
                      label: const Text('새 노트로 필기 시작',
                          style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00897B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  // 에디터에서 진입했을 때: 배경으로 설정 / 이미지로 삽입
                  if (widget.entryMode == ScanEntryMode.fromEditor) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isProcessing ? null : _setAsBackground,
                            icon: const Icon(Icons.wallpaper, size: 18),
                            label: const Text('배경으로 설정',
                                style: TextStyle(fontSize: 13)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isProcessing ? null : _insertToNote,
                            icon: const Icon(Icons.add_photo_alternate,
                                size: 18),
                            label: const Text('노트에 삽입',
                                style: TextStyle(fontSize: 13)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 새 노트로 바로 열기 — 스캔 이미지를 배경으로 설정한 에디터 열기
  Future<void> _openAsNewNote() async {
    setState(() => _isProcessing = true);

    try {
      // 앱 배경 폴더에 복사
      final savedPath = await _copyToBackgrounds(_currentImagePath);

      debugPrint('[스캔→노트] 배경 이미지 저장: $savedPath');

      if (!mounted) return;

      // GoRouter 인스턴스를 pop 전에 캡처
      final router = GoRouter.of(context);

      // imperative 스택(FilterPage, CropPage, ScannerPage)을 모두 pop
      // → GoRouter가 관리하는 홈(/) 라우트만 남음
      Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);

      // GoRouter로 에디터 열기 (캡처한 router 인스턴스 사용)
      router.go('/editor/new', extra: {
        'initialBackgroundImagePath': savedPath,
      });
    } catch (e) {
      debugPrint('[스캔→노트] 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('노트 열기 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 스캔 화면 스택을 모두 pop하여 에디터로 복귀
  void _popScanStack() {
    // 에디터에서 push한 ScannerPage('scanner_from_editor')까지 pop
    // ScannerPage 자체도 pop하여 에디터로 복귀
    var hitScanner = false;
    Navigator.of(context).popUntil((route) {
      if (route.settings.name == 'scanner_from_editor') {
        hitScanner = true;
        return false; // scanner_from_editor도 pop 대상
      }
      if (hitScanner) return true; // scanner 이전 라우트(에디터)에서 멈춤
      return route.isFirst; // 안전장치
    });
  }

  /// 노트에 이미지로 삽입 (에디터에서 진입 시)
  Future<void> _insertToNote() async {
    setState(() => _isProcessing = true);
    try {
      final savedPath = await _copyToImages(_currentImagePath);
      if (mounted) {
        widget.onResult?.call(savedPath, ScanInsertMode.image);
        _popScanStack();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삽입 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 배경으로 설정 (에디터에서 진입 시)
  Future<void> _setAsBackground() async {
    setState(() => _isProcessing = true);
    try {
      final savedPath = await _copyToBackgrounds(_currentImagePath);
      if (mounted) {
        widget.onResult?.call(savedPath, ScanInsertMode.background);
        _popScanStack();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('배경 설정 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 앱 배경 폴더에 이미지 복사
  Future<String> _copyToBackgrounds(String imagePath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final bgDir = Directory(
        '${appDir.path}${Platform.pathSeparator}Winote${Platform.pathSeparator}backgrounds');
    if (!await bgDir.exists()) {
      await bgDir.create(recursive: true);
    }
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}${path.extension(imagePath)}';
    final savedPath = '${bgDir.path}${Platform.pathSeparator}$fileName';
    await File(imagePath).copy(savedPath);
    return savedPath;
  }

  /// 앱 이미지 폴더에 이미지 복사
  Future<String> _copyToImages(String imagePath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(
        '${appDir.path}${Platform.pathSeparator}Winote${Platform.pathSeparator}images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}${path.extension(imagePath)}';
    final savedPath = '${imagesDir.path}${Platform.pathSeparator}$fileName';
    await File(imagePath).copy(savedPath);
    return savedPath;
  }
}
