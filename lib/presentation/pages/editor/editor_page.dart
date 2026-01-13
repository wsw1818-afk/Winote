import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../../../domain/entities/stroke.dart';
import '../../../core/providers/drawing_state.dart';
import '../../../core/services/note_storage_service.dart';
import '../../../core/services/pdf_export_service.dart';
import '../../../core/services/stroke_smoothing_service.dart';
import '../../widgets/canvas/drawing_canvas.dart';
import '../../widgets/toolbar/drawing_toolbar.dart';
import '../../widgets/toolbar/quick_toolbar.dart';

class EditorPage extends ConsumerStatefulWidget {
  final String noteId;

  const EditorPage({
    super.key,
    required this.noteId,
  });

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  final GlobalKey<DrawingCanvasState> _canvasKey = GlobalKey();
  final NoteStorageService _storageService = NoteStorageService.instance;

  // Note state
  Note? _currentNote;
  bool _isLoading = true;
  bool _hasChanges = false;

  // Page state
  int _currentPageIndex = 0;

  // Drawing tool state
  DrawingTool _currentTool = DrawingTool.pen;
  Color _currentColor = Colors.black;
  double _currentWidth = 2.0;
  PageTemplate _currentTemplate = PageTemplate.grid;

  // Stroke smoothing
  SmoothingLevel _smoothingLevel = SmoothingLevel.medium;

  // Track undo/redo state
  bool _canUndo = false;
  bool _canRedo = false;

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  Future<void> _loadNote() async {
    setState(() => _isLoading = true);

    if (widget.noteId == 'new') {
      // Create new note
      _currentNote = _storageService.createNewNote();
    } else {
      // Load existing note
      _currentNote = await _storageService.loadNote(widget.noteId);
      if (_currentNote == null) {
        // Note not found, create new
        _currentNote = _storageService.createNewNote();
      }
    }

    setState(() => _isLoading = false);

    // Load strokes for current page into canvas
    _loadCurrentPageStrokes();
  }

  void _loadCurrentPageStrokes() {
    if (_currentNote == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Get strokes from current page by index
      List<Stroke> strokes = [];
      if (_currentPageIndex < _currentNote!.pages.length) {
        strokes = _currentNote!.pages[_currentPageIndex].strokes;
      }
      _canvasKey.currentState?.loadStrokes(strokes);
      _updateUndoRedoState();
    });
  }

  /// Save current canvas strokes to current page before switching
  void _saveCurrentPageStrokes() {
    if (_currentNote == null) return;

    final strokes = _canvasKey.currentState?.strokes ?? [];
    // Use page number from pages array, not index
    if (_currentPageIndex < _currentNote!.pages.length) {
      final pageNumber = _currentNote!.pages[_currentPageIndex].pageNumber;
      _currentNote = _currentNote!.updatePageStrokes(pageNumber, strokes);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _showRenameDialog,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_currentNote?.title ?? '새 노트'),
              if (_hasChanges)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Text('*', style: TextStyle(color: Colors.orange)),
                ),
              const SizedBox(width: 4),
              const Icon(Icons.edit, size: 16),
            ],
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _onBackPressed,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: '저장',
            onPressed: _saveNote,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showMoreMenu,
          ),
        ],
      ),
      body: Column(
        children: [
          // Toolbar
          DrawingToolbar(
            currentTool: _currentTool,
            currentColor: _currentColor,
            currentWidth: _currentWidth,
            canUndo: _canUndo,
            canRedo: _canRedo,
            onUndo: () {
              _canvasKey.currentState?.undo();
              _updateUndoRedoState();
            },
            onRedo: () {
              _canvasKey.currentState?.redo();
              _updateUndoRedoState();
            },
            onClear: _showClearConfirmDialog,
            onToolChanged: (tool) {
              setState(() => _currentTool = tool);
            },
            onColorChanged: (color) {
              setState(() => _currentColor = color);
            },
            onWidthChanged: (width) {
              setState(() => _currentWidth = width);
            },
          ),
          // Canvas with floating quick toolbar
          Expanded(
            child: Stack(
              children: [
                DrawingCanvas(
                  key: _canvasKey,
                  strokeColor: _currentColor,
                  strokeWidth: _currentWidth,
                  toolType: _toolTypeFromDrawingTool(_currentTool),
                  drawingTool: _currentTool,
                  pageTemplate: _currentTemplate,
                  onStrokesChanged: (strokes) {
                    _updateUndoRedoState();
                    if (!_hasChanges) {
                      setState(() => _hasChanges = true);
                    }
                  },
                ),
                // Floating quick toolbar at bottom center
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: QuickToolbar(
                      currentTool: _currentTool,
                      currentColor: _currentColor,
                      currentWidth: _currentWidth,
                      currentTemplate: _currentTemplate,
                      canUndo: _canUndo,
                      canRedo: _canRedo,
                      hasSelection: _canvasKey.currentState?.selectedStrokes.isNotEmpty ?? false,
                      onToolChanged: (tool) {
                        print('[EDITOR] Tool changed to: $tool'); // 디버그 로그
                        setState(() => _currentTool = tool);
                        // Clear selection when switching away from lasso
                        if (tool != DrawingTool.lasso) {
                          _canvasKey.currentState?.clearSelection();
                        }
                      },
                      onColorChanged: (color) {
                        setState(() => _currentColor = color);
                      },
                      onWidthChanged: (width) {
                        setState(() => _currentWidth = width);
                      },
                      onTemplateChanged: (template) {
                        setState(() => _currentTemplate = template);
                      },
                      onUndo: () {
                        _canvasKey.currentState?.undo();
                        _updateUndoRedoState();
                      },
                      onRedo: () {
                        _canvasKey.currentState?.redo();
                        _updateUndoRedoState();
                      },
                      onCopySelection: () {
                        _canvasKey.currentState?.copySelection();
                        _updateUndoRedoState();
                        setState(() => _hasChanges = true);
                      },
                      onDeleteSelection: () {
                        _canvasKey.currentState?.deleteSelection();
                        _updateUndoRedoState();
                        setState(() => _hasChanges = true);
                      },
                      onClearSelection: () {
                        _canvasKey.currentState?.clearSelection();
                        setState(() {});
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Page navigation bar
          _buildPageNavigationBar(),
        ],
      ),
    );
  }

  Widget _buildPageNavigationBar() {
    final pageCount = _currentNote?.pageCount ?? 1;

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        children: [
          // Previous page button
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _currentPageIndex > 0 ? _goToPreviousPage : null,
            tooltip: '이전 페이지',
          ),

          // Page indicator and list
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: _showPageListDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_currentPageIndex + 1} / $pageCount',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.expand_more, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Next page button
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _currentPageIndex < pageCount - 1 ? _goToNextPage : null,
            tooltip: '다음 페이지',
          ),

          // Add page button
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addNewPage,
            tooltip: '페이지 추가',
          ),
        ],
      ),
    );
  }

  void _goToPreviousPage() {
    if (_currentPageIndex > 0) {
      _saveCurrentPageStrokes();
      setState(() => _currentPageIndex--);
      _loadCurrentPageStrokes();
    }
  }

  void _goToNextPage() {
    final pageCount = _currentNote?.pageCount ?? 1;
    if (_currentPageIndex < pageCount - 1) {
      _saveCurrentPageStrokes();
      setState(() => _currentPageIndex++);
      _loadCurrentPageStrokes();
    }
  }

  void _goToPage(int pageIndex) {
    if (pageIndex != _currentPageIndex) {
      _saveCurrentPageStrokes();
      setState(() => _currentPageIndex = pageIndex);
      _loadCurrentPageStrokes();
    }
  }

  void _addNewPage() {
    if (_currentNote == null) return;

    _saveCurrentPageStrokes();
    _currentNote = _currentNote!.addPage();
    _currentPageIndex = _currentNote!.pageCount - 1;
    _hasChanges = true;

    setState(() {});
    _loadCurrentPageStrokes();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('페이지 ${_currentPageIndex + 1} 추가됨')),
    );
  }

  void _showPageListDialog() {
    final pageCount = _currentNote?.pageCount ?? 1;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('페이지 선택'),
        content: SizedBox(
          width: 300,
          height: 400,
          child: ListView.builder(
            itemCount: pageCount,
            itemBuilder: (context, index) {
              final page = _currentNote!.pages[index];
              final isCurrentPage = index == _currentPageIndex;
              final strokeCount = page.strokes.length;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isCurrentPage ? Colors.blue : Colors.grey[300],
                  foregroundColor: isCurrentPage ? Colors.white : Colors.black,
                  child: Text('${index + 1}'),
                ),
                title: Text('페이지 ${index + 1}'),
                subtitle: Text('$strokeCount개 스트로크'),
                selected: isCurrentPage,
                onTap: () {
                  Navigator.pop(context);
                  _goToPage(index);
                },
                trailing: pageCount > 1
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () {
                          Navigator.pop(context);
                          _showDeletePageDialog(index);
                        },
                      )
                    : null,
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _addNewPage();
            },
            child: const Text('페이지 추가'),
          ),
        ],
      ),
    );
  }

  void _showDeletePageDialog(int pageIndex) {
    if (_currentNote == null || _currentNote!.pageCount <= 1) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('페이지 삭제'),
        content: Text('페이지 ${pageIndex + 1}을(를) 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePage(pageIndex);
            },
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _deletePage(int pageIndex) {
    if (_currentNote == null || _currentNote!.pageCount <= 1) return;

    final pageNumber = _currentNote!.pages[pageIndex].pageNumber;
    _currentNote = _currentNote!.deletePage(pageNumber);
    _hasChanges = true;

    // Adjust current page index if needed
    if (_currentPageIndex >= _currentNote!.pageCount) {
      _currentPageIndex = _currentNote!.pageCount - 1;
    }

    setState(() {});
    _loadCurrentPageStrokes();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('페이지가 삭제되었습니다')),
    );
  }

  ToolType _toolTypeFromDrawingTool(DrawingTool tool) {
    switch (tool) {
      case DrawingTool.pen:
        return ToolType.pen;
      case DrawingTool.highlighter:
        return ToolType.highlighter;
      case DrawingTool.eraser:
        return ToolType.eraser;
      case DrawingTool.lasso:
        return ToolType.pen; // Lasso doesn't draw strokes
    }
  }

  void _updateUndoRedoState() {
    final canvasState = _canvasKey.currentState;
    if (canvasState != null) {
      setState(() {
        _canUndo = canvasState.canUndo;
        _canRedo = canvasState.canRedo;
      });
    }
  }

  Future<void> _saveNote() async {
    if (_currentNote == null) return;

    // Save current page strokes first
    _saveCurrentPageStrokes();

    await _storageService.saveNote(_currentNote!);

    setState(() => _hasChanges = false);

    if (mounted) {
      final totalStrokes = _currentNote!.strokes.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장됨: ${_currentNote!.pageCount}페이지, $totalStrokes개의 스트로크')),
      );
    }
  }

  void _onBackPressed() {
    if (_hasChanges) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('저장하지 않은 변경사항'),
          content: const Text('변경사항을 저장하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                context.pop();
              },
              child: const Text('저장 안 함'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _saveNote();
                if (mounted) context.pop();
              },
              child: const Text('저장'),
            ),
          ],
        ),
      );
    } else {
      context.pop();
    }
  }

  void _showRenameDialog() {
    final controller = TextEditingController(text: _currentNote?.title ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('노트 이름 변경'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '노트 이름',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty && _currentNote != null) {
                setState(() {
                  _currentNote = _currentNote!.copyWith(title: controller.text);
                  _hasChanges = true;
                });
              }
              Navigator.pop(context);
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _showClearConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('전체 삭제'),
        content: const Text('현재 페이지의 모든 필기를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              _canvasKey.currentState?.clear();
              _updateUndoRedoState();
              Navigator.pop(context);
            },
            child: const Text(
              '삭제',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_photo_alternate),
              title: const Text('이미지 삽입'),
              onTap: () {
                Navigator.pop(context);
                _insertImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('텍스트 삽입'),
              onTap: () {
                Navigator.pop(context);
                _insertTextBox();
              },
            ),
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('이미지로 내보내기'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('이미지 내보내기 기능 구현 예정')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('PDF로 내보내기'),
              onTap: () {
                Navigator.pop(context);
                _exportToPdf();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('공유'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('공유 기능 구현 예정')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('노트 정보'),
              onTap: () {
                Navigator.pop(context);
                _showNoteInfo();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.auto_fix_high),
              title: const Text('필기 보정'),
              subtitle: Text(_getSmoothingLevelText(_smoothingLevel)),
              onTap: () {
                Navigator.pop(context);
                _showSmoothingDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _insertImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile == null) return;

      // Copy image to app's directory for persistence
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}${Platform.pathSeparator}Winote${Platform.pathSeparator}images');
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      final fileName = '${DateTime.now().millisecondsSinceEpoch}${path.extension(pickedFile.path)}';
      final savedPath = '${imagesDir.path}${Platform.pathSeparator}$fileName';

      await File(pickedFile.path).copy(savedPath);

      // Add image to canvas
      await _canvasKey.currentState?.addImage(savedPath);

      setState(() => _hasChanges = true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미지가 삽입되었습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지 삽입 실패: $e')),
        );
      }
    }
  }

  void _insertTextBox() {
    _canvasKey.currentState?.addTextBox();
    setState(() => _hasChanges = true);
  }

  void _showNoteInfo() {
    final strokes = _canvasKey.currentState?.strokes ?? [];
    int totalPoints = 0;
    for (final stroke in strokes) {
      totalPoints += stroke.points.length;
    }

    final totalStrokes = _currentNote?.strokes.length ?? 0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('노트 정보'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('총 페이지: ${_currentNote?.pageCount ?? 1}'),
            Text('총 스트로크: $totalStrokes'),
            const Divider(),
            Text('현재 페이지: ${_currentPageIndex + 1}'),
            Text('현재 페이지 스트로크: ${strokes.length}'),
            Text('현재 페이지 포인트: $totalPoints'),
            const Divider(),
            Text('노트 ID: ${widget.noteId}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  String _getSmoothingLevelText(SmoothingLevel level) {
    switch (level) {
      case SmoothingLevel.none:
        return '없음 (원본 그대로)';
      case SmoothingLevel.light:
        return '약하게 (빠른 필기용)';
      case SmoothingLevel.medium:
        return '보통 (권장)';
      case SmoothingLevel.strong:
        return '강하게 (악필 교정)';
    }
  }

  void _showSmoothingDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('필기 보정 강도'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '필기 시 떨림을 보정하고 부드러운 곡선으로 만들어줍니다.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ...SmoothingLevel.values.map((level) => RadioListTile<SmoothingLevel>(
              title: Text(_getSmoothingLevelText(level)),
              subtitle: Text(_getSmoothingDescription(level)),
              value: level,
              groupValue: _smoothingLevel,
              onChanged: (value) {
                if (value != null) {
                  setState(() => _smoothingLevel = value);
                  StrokeSmoothingService.instance.level = value;
                  Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('필기 보정: ${_getSmoothingLevelText(value)}')),
                  );
                }
              },
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  String _getSmoothingDescription(SmoothingLevel level) {
    switch (level) {
      case SmoothingLevel.none:
        return '입력 그대로 표시';
      case SmoothingLevel.light:
        return '미세한 떨림만 제거';
      case SmoothingLevel.medium:
        return '자연스러운 곡선 보정';
      case SmoothingLevel.strong:
        return '강력한 스무딩 적용';
    }
  }

  Future<void> _exportToPdf() async {
    // Save current page first
    _saveCurrentPageStrokes();

    final allStrokes = _currentNote?.strokes ?? [];
    if (allStrokes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('내보낼 필기가 없습니다')),
        );
      }
      return;
    }

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('PDF 생성 중...'),
          ],
        ),
      ),
    );

    try {
      // Get canvas size from render box
      final renderBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
      final canvasSize = renderBox?.size ?? const Size(800, 600);

      final pdfService = PdfExportService.instance;
      final filePath = await pdfService.exportToPdfSmooth(
        strokes: allStrokes,
        title: _currentNote?.title ?? '새 노트',
        canvasSize: canvasSize,
      );

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      if (filePath != null) {
        // Show success dialog with options
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('PDF 내보내기 완료'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PDF 파일이 생성되었습니다.'),
                  const SizedBox(height: 8),
                  Text(
                    filePath,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('확인'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    // Open the PDF file
                    final uri = Uri.file(filePath);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                  child: const Text('파일 열기'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    // Open the exports folder
                    final exportDir = await pdfService.getExportsDirectory();
                    final uri = Uri.file(exportDir);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                  child: const Text('폴더 열기'),
                ),
              ],
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PDF 생성 실패')),
          );
        }
      }
    } catch (e) {
      // Close loading dialog if still open
      if (mounted) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF 생성 오류: $e')),
        );
      }
    }
  }
}
