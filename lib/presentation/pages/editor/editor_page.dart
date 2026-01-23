import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../../domain/entities/stroke.dart';
import '../../../domain/entities/canvas_shape.dart';
import '../../../domain/entities/canvas_table.dart';
import '../../../core/providers/drawing_state.dart';
import '../../../core/services/note_storage_service.dart';
import '../../../core/services/pdf_export_service.dart';
import '../../../core/services/image_export_service.dart';
import '../../../core/services/stroke_smoothing_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/services/backup_service.dart';
import '../../widgets/canvas/drawing_canvas.dart';
import '../../widgets/toolbar/drawing_toolbar.dart';
import '../../widgets/toolbar/quick_toolbar.dart';
import '../../widgets/toolbar/image_edit_toolbar.dart';
import '../settings/settings_page.dart';

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

  // Page state
  int _currentPageIndex = 0;

  // Drawing tool state
  DrawingTool _currentTool = DrawingTool.pen;

  // 펜 설정 (별도 저장)
  Color _penColor = Colors.black;
  double _penWidth = 2.0;

  // 형광펜 설정 (별도 저장)
  Color _highlighterColor = const Color(0xFFFFEB3B); // 노랑
  double _highlighterWidth = 20.0;
  double _highlighterOpacity = 0.4;

  // 지우개 설정
  double _eraserWidth = 20.0;

  PageTemplate _currentTemplate = PageTemplate.grid;
  String? _backgroundImagePath; // 커스텀 배경 이미지 경로
  PageTemplate? _overlayTemplate; // 배경 이미지 위에 표시할 템플릿

  // Stroke smoothing
  SmoothingLevel _smoothingLevel = SmoothingLevel.medium;

  // Lasso color (from settings)
  Color _lassoColor = const Color(0xFF2196F3);

  // Laser pointer color
  Color _laserPointerColor = Colors.red;

  // Presentation highlighter fade mode
  bool _presentationHighlighterFadeEnabled = true;
  double _presentationHighlighterFadeSpeed = 1.0; // 1.0 = 기본(1.5초), 0.5 = 느림(3초), 2.0 = 빠름(0.75초)

  // Track undo/redo state - ValueNotifier로 불필요한 rebuild 방지
  final ValueNotifier<bool> _canUndoNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _canRedoNotifier = ValueNotifier(false);

  // 변경 상태 추적 - setState 호출 최소화
  bool _hasChanges = false;
  bool _pendingHasChangesUpdate = false;

  // Auto-save
  Timer? _autoSaveTimer;
  bool _autoSaveEnabled = true;
  int _autoSaveDelay = 3; // seconds

  // Image editing state
  bool _showImageEditToolbar = false;

  // 성능 최적화: 슬라이더 변경 디바운스 타이머
  Timer? _sliderDebounceTimer;

  // Debug overlay (from settings)
  bool _showDebugOverlay = false;

  // 패널 닫기 콜백 (캔버스 터치 시 패널 닫기 위해)
  VoidCallback? _closePanelCallback;

  /// 현재 페이지의 PDF 배경 정보 가져오기
  CanvasShape? _getCurrentPagePdfBackground() {
    if (_currentNote == null) return null;
    if (_currentPageIndex >= _currentNote!.pages.length) return null;

    final shapes = _currentNote!.pages[_currentPageIndex].shapes;
    for (final shape in shapes) {
      if (shape.type == CanvasShapeType.pdfBackground && shape.pdfPath != null) {
        return shape;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadNote();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _sliderDebounceTimer?.cancel();
    _canUndoNotifier.dispose();
    _canRedoNotifier.dispose();
    super.dispose();
  }

  /// 슬라이더 변경 시 디바운스 적용 (성능 최적화)
  void _debouncedSetHasChanges() {
    _sliderDebounceTimer?.cancel();
    _sliderDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted && !_hasChanges) {
        setState(() => _hasChanges = true);
      }
    });
  }

  void _loadSettings() {
    final settings = SettingsService.instance;
    _autoSaveEnabled = settings.autoSaveEnabled;
    _autoSaveDelay = settings.autoSaveDelay;
    _penWidth = settings.defaultPenWidth;
    _eraserWidth = settings.defaultEraserWidth;
    _currentTemplate = settings.defaultTemplate;
    _lassoColor = settings.lassoColor;
    _showDebugOverlay = settings.showDebugOverlay;
  }

  /// 현재 도구에 맞는 색상 반환
  Color get _currentColor {
    switch (_currentTool) {
      case DrawingTool.pen:
      case DrawingTool.shapeLine:
      case DrawingTool.shapeRectangle:
      case DrawingTool.shapeCircle:
      case DrawingTool.shapeArrow:
        return _penColor;
      case DrawingTool.highlighter:
        return _highlighterColor;
      default:
        return _penColor;
    }
  }

  /// 현재 도구에 맞는 굵기 반환
  double get _currentWidth {
    switch (_currentTool) {
      case DrawingTool.pen:
      case DrawingTool.shapeLine:
      case DrawingTool.shapeRectangle:
      case DrawingTool.shapeCircle:
      case DrawingTool.shapeArrow:
        return _penWidth;
      case DrawingTool.highlighter:
        return _highlighterWidth;
      default:
        return _penWidth;
    }
  }

  void _scheduleAutoSave() {
    if (!_autoSaveEnabled) return;

    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(Duration(seconds: _autoSaveDelay), () {
      if (_hasChanges && _currentNote != null) {
        _autoSave();
      }
    });
  }

  /// 변경 상태 UI 업데이트를 지연시켜 불필요한 rebuild 방지
  void _scheduleHasChangesUpdate() {
    if (_pendingHasChangesUpdate) return;
    _pendingHasChangesUpdate = true;

    // 다음 프레임에서 한 번만 setState 호출
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pendingHasChangesUpdate) {
        _pendingHasChangesUpdate = false;
        setState(() {}); // AppBar 타이틀의 * 표시 업데이트
      }
    });
  }

  Future<void> _autoSave() async {
    if (_currentNote == null || !_hasChanges) return;

    // Save current page strokes first
    _saveCurrentPageStrokes();

    await _storageService.saveNote(_currentNote!);

    if (mounted) {
      setState(() => _hasChanges = false);
    }
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
        final page = _currentNote!.pages[_currentPageIndex];
        strokes = page.strokes;

        // 페이지별 배경 이미지 및 오버레이 템플릿 로드
        setState(() {
          _backgroundImagePath = page.backgroundImagePath;
          if (page.overlayTemplateIndex != null) {
            _overlayTemplate = PageTemplate.values[page.overlayTemplateIndex!];
          } else {
            _overlayTemplate = null;
          }
          // 배경 이미지가 있으면 템플릿을 customImage로, 없으면 templateIndex 사용
          if (page.backgroundImagePath != null) {
            _currentTemplate = PageTemplate.customImage;
          } else if (page.templateIndex != null) {
            _currentTemplate = PageTemplate.values[page.templateIndex!];
          }
        });
      }
      _canvasKey.currentState?.loadStrokes(strokes);
      _updateUndoRedoState();
    });
  }

  /// Save current canvas strokes to current page before switching
  void _saveCurrentPageStrokes() {
    if (_currentNote == null) return;

    final strokes = _canvasKey.currentState?.strokes ?? [];
    final canvasShapes = _canvasKey.currentState?.shapes ?? [];
    // Use page number from pages array, not index
    if (_currentPageIndex < _currentNote!.pages.length) {
      final pageNumber = _currentNote!.pages[_currentPageIndex].pageNumber;
      _currentNote = _currentNote!.updatePageStrokes(pageNumber, strokes);

      // PDF 배경 shape를 보존하면서 캔버스 shapes 업데이트
      // 기존 페이지의 PDF 배경 shape 찾기
      final existingShapes = _currentNote!.pages[_currentPageIndex].shapes;
      final pdfBackgrounds = existingShapes
          .where((s) => s.type == CanvasShapeType.pdfBackground)
          .toList();

      // PDF 배경이 아닌 캔버스 shapes + 기존 PDF 배경 병합
      final nonPdfShapes = canvasShapes
          .where((s) => s.type != CanvasShapeType.pdfBackground)
          .toList();
      final mergedShapes = [...pdfBackgrounds, ...nonPdfShapes];

      _currentNote = _currentNote!.updatePageShapes(pageNumber, mergedShapes);

      // 배경 이미지 및 오버레이 템플릿 저장
      _currentNote = _currentNote!.updatePageBackground(
        pageNumber,
        backgroundImagePath: _backgroundImagePath,
        clearBackgroundImage: _backgroundImagePath == null,
        overlayTemplateIndex: _overlayTemplate?.index,
        clearOverlayTemplateIndex: _overlayTemplate == null,
        templateIndex: _currentTemplate.index,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): const UndoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): const RedoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): const RedoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): const SaveIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          UndoIntent: CallbackAction<UndoIntent>(
            onInvoke: (_) {
              if (_canUndoNotifier.value) {
                _canvasKey.currentState?.undo();
                _updateUndoRedoState();
              }
              return null;
            },
          ),
          RedoIntent: CallbackAction<RedoIntent>(
            onInvoke: (_) {
              if (_canRedoNotifier.value) {
                _canvasKey.currentState?.redo();
                _updateUndoRedoState();
              }
              return null;
            },
          ),
          SaveIntent: CallbackAction<SaveIntent>(
            onInvoke: (_) {
              _saveNote();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
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
          // 즐겨찾기 토글 버튼
          IconButton(
            icon: Icon(
              _currentNote?.isFavorite == true ? Icons.star : Icons.star_border,
              color: _currentNote?.isFavorite == true ? Colors.amber : null,
            ),
            tooltip: _currentNote?.isFavorite == true ? '즐겨찾기 해제' : '즐겨찾기 추가',
            onPressed: _toggleFavorite,
          ),
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
          // Quick toolbar - 노트 영역 위에 배치
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: Colors.grey[100],
            child: Center(
              child: QuickToolbar(
                currentTool: _currentTool,
                currentColor: _penColor,
                highlighterColor: _highlighterColor,
                currentWidth: _penWidth,
                highlighterWidth: _highlighterWidth,
                eraserWidth: _eraserWidth,
                highlighterOpacity: _highlighterOpacity,
                currentTemplate: _currentTemplate,
                hasSelection: _canvasKey.currentState?.selectedStrokes.isNotEmpty ?? false,
                onToolChanged: (tool) {
                  setState(() => _currentTool = tool);
                  if (tool != DrawingTool.lasso) {
                    _canvasKey.currentState?.clearSelection();
                  }
                },
                onColorChanged: (color) {
                  setState(() => _penColor = color);
                },
                onHighlighterColorChanged: (color) {
                  setState(() => _highlighterColor = color);
                },
                onWidthChanged: (width) {
                  setState(() => _penWidth = width);
                },
                onHighlighterWidthChanged: (width) {
                  setState(() => _highlighterWidth = width);
                },
                onEraserWidthChanged: (width) {
                  setState(() => _eraserWidth = width);
                },
                onHighlighterOpacityChanged: (opacity) {
                  setState(() => _highlighterOpacity = opacity);
                },
                onTemplateChanged: (template) {
                  setState(() {
                    if (_backgroundImagePath != null) {
                      if (template == PageTemplate.blank) {
                        _overlayTemplate = null;
                      } else {
                        _overlayTemplate = template;
                      }
                    } else {
                      _currentTemplate = template;
                    }
                    _hasChanges = true;
                  });
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
                onInsertImage: _insertImage,
                onInsertText: _insertTextBox,
                onInsertTable: _showInsertTableDialog,
                onSelectBackgroundImage: _selectBackgroundImage,
                onClearBackgroundImage: _clearBackgroundImage,
                hasBackgroundImage: _backgroundImagePath != null,
                overlayTemplate: _overlayTemplate,
                laserPointerColor: _laserPointerColor,
                onLaserPointerColorChanged: (color) {
                  setState(() => _laserPointerColor = color);
                },
                presentationHighlighterFadeEnabled: _presentationHighlighterFadeEnabled,
                onPresentationHighlighterFadeChanged: (enabled) {
                  setState(() => _presentationHighlighterFadeEnabled = enabled);
                },
                presentationHighlighterFadeSpeed: _presentationHighlighterFadeSpeed,
                onPresentationHighlighterFadeSpeedChanged: (speed) {
                  setState(() => _presentationHighlighterFadeSpeed = speed);
                },
                onPanelOpened: (closeCallback) {
                  _closePanelCallback = closeCallback;
                },
                // Undo/Redo/Save/Clear
                onUndo: () {
                  _canvasKey.currentState?.undo();
                  _updateUndoRedoState();
                },
                onRedo: () {
                  _canvasKey.currentState?.redo();
                  _updateUndoRedoState();
                },
                onSave: _saveNote,
                onClear: _showClearConfirmDialog,
                canUndo: _canUndoNotifier.value,
                canRedo: _canRedoNotifier.value,
                hasChanges: _hasChanges,
              ),
            ),
          ),
          // Canvas - A4 비율로 화면 가득 채움
          Expanded(
            child: Stack(
              children: [
                // PDF 배경 (있는 경우)
                if (_getCurrentPagePdfBackground() != null)
                  Positioned.fill(
                    child: _buildPdfBackground(),
                  ),
                // 용지 - 화면 전체를 A4 비율로 채움
                Positioned.fill(
                  child: Container(
                    color: _getCurrentPagePdfBackground() == null ? Colors.white : Colors.transparent,
                    child: DrawingCanvas(
                            key: _canvasKey,
                            strokeColor: _currentColor,
                            strokeWidth: _currentWidth,
                            highlighterColor: _highlighterColor, // 형광펜 전용 색상
                            highlighterWidth: _highlighterWidth, // 형광펜 전용 굵기
                            eraserWidth: _eraserWidth,
                            highlighterOpacity: _highlighterOpacity,
                            toolType: _toolTypeFromDrawingTool(_currentTool),
                            drawingTool: _currentTool,
                            pageTemplate: _currentTemplate,
                            backgroundImagePath: _backgroundImagePath,
                            overlayTemplate: _overlayTemplate,
                            lassoColor: _currentColor,
                            laserPointerColor: _laserPointerColor,
                            presentationHighlighterFadeEnabled: _presentationHighlighterFadeEnabled,
                            presentationHighlighterFadeSpeed: _presentationHighlighterFadeSpeed,
                            showDebugOverlay: _showDebugOverlay,
                            initialShapes: _currentNote?.getShapesForPage(_currentPageIndex),
                            onStrokesChanged: (strokes) {
                              _updateUndoRedoState();
                              // setState 없이 내부 상태만 변경 (AppBar 타이틀에 * 표시 필요시에만 rebuild)
                              if (!_hasChanges) {
                                _hasChanges = true;
                                // 타이틀 업데이트가 필요하면 지연된 단일 setState
                                _scheduleHasChangesUpdate();
                              }
                              _scheduleAutoSave();
                            },
                            onShapesChanged: (shapes) {
                              _updateUndoRedoState();
                              if (!_hasChanges) {
                                _hasChanges = true;
                                _scheduleHasChangesUpdate();
                              }
                              _scheduleAutoSave();
                            },
                            onImageSelectionChanged: (hasSelection) {
                              setState(() {
                                _showImageEditToolbar = hasSelection;
                              });
                            },
                            onCanvasTouchStart: () {
                              // 캔버스 터치 시 열린 패널 닫기
                              if (_closePanelCallback != null) {
                                _closePanelCallback!();
                                _closePanelCallback = null;
                              }
                            },
                    ),
                  ),
                ),
                  // Image edit toolbar (floating at top right, Transform 외부)
                  if (_showImageEditToolbar)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: ImageEditToolbar(
                        rotation: _canvasKey.currentState?.selectedImage?.rotation ?? 0,
                        opacity: _canvasKey.currentState?.selectedImage?.opacity ?? 1.0,
                        onRotationChanged: (rotation) {
                          _canvasKey.currentState?.updateImageRotation(rotation);
                          // 성능 최적화: 슬라이더 조작 중 setState 디바운스
                          _debouncedSetHasChanges();
                        },
                        onOpacityChanged: (opacity) {
                          _canvasKey.currentState?.updateImageOpacity(opacity);
                          // 성능 최적화: 슬라이더 조작 중 setState 디바운스
                          _debouncedSetHasChanges();
                        },
                        onDelete: () {
                          _canvasKey.currentState?.deleteSelectedImage();
                          setState(() {
                            _showImageEditToolbar = false;
                            _hasChanges = true;
                          });
                        },
                        onClose: () {
                          _canvasKey.currentState?.clearImageSelection();
                          setState(() => _showImageEditToolbar = false);
                        },
                      ),
                    ),
              ],
            ),
          ),
          // Page navigation bar
          _buildPageNavigationBar(),
        ],
      ),
    ),
        ),
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 가운데 정렬된 페이지 네비게이션 그룹
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Previous page button
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _currentPageIndex > 0 ? _goToPreviousPage : null,
                  tooltip: '이전 페이지',
                  iconSize: 24,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                ),

                // Page indicator
                GestureDetector(
                  onTap: _showPageListDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                        const SizedBox(width: 4),
                        const Icon(Icons.expand_more, size: 18),
                      ],
                    ),
                  ),
                ),

                // Next page button
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _currentPageIndex < pageCount - 1 ? _goToNextPage : null,
                  tooltip: '다음 페이지',
                  iconSize: 24,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Add page button (분리)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: IconButton(
              icon: const Icon(Icons.add),
              onPressed: _addNewPage,
              tooltip: '페이지 추가',
              iconSize: 24,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
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
  }

  void _showPageListDialog() {
    final pageCount = _currentNote?.pageCount ?? 1;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Text('페이지 선택'),
            const Spacer(),
            Text(
              '$pageCount페이지',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          height: 500,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.75, // A4 비율에 가깝게
            ),
            itemCount: pageCount,
            itemBuilder: (context, index) {
              final page = _currentNote!.pages[index];
              final isCurrentPage = index == _currentPageIndex;
              final strokeCount = page.strokes.length;

              return _buildPageThumbnail(
                page: page,
                pageIndex: index,
                isCurrentPage: isCurrentPage,
                strokeCount: strokeCount,
                canDelete: pageCount > 1,
                onTap: () {
                  Navigator.pop(context);
                  _goToPage(index);
                },
                onDelete: () {
                  Navigator.pop(context);
                  _showDeletePageDialog(index);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _addNewPage();
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('페이지 추가'),
          ),
        ],
      ),
    );
  }

  /// 페이지 썸네일 위젯 빌드
  Widget _buildPageThumbnail({
    required NotePage page,
    required int pageIndex,
    required bool isCurrentPage,
    required int strokeCount,
    required bool canDelete,
    required VoidCallback onTap,
    required VoidCallback onDelete,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isCurrentPage ? Colors.blue : Colors.grey[300]!,
            width: isCurrentPage ? 2 : 1,
          ),
          boxShadow: isCurrentPage
              ? [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            // 썸네일 미리보기
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: page.strokes.isEmpty
                    ? Center(
                        child: Icon(
                          Icons.draw_outlined,
                          size: 32,
                          color: Colors.grey[300],
                        ),
                      )
                    : CustomPaint(
                        painter: _PageThumbnailPainter(strokes: page.strokes),
                      ),
              ),
            ),
            // 페이지 번호 배지
            Positioned(
              left: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isCurrentPage ? Colors.blue : Colors.grey[700],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${pageIndex + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            // 삭제 버튼
            if (canDelete)
              Positioned(
                right: 2,
                top: 2,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onDelete,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            // 스트로크 수 표시 (하단)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.5),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(7),
                    bottomRight: Radius.circular(7),
                  ),
                ),
                child: Text(
                  strokeCount > 0 ? '$strokeCount개' : '빈 페이지',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          ],
        ),
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
      case DrawingTool.laserPointer:
      case DrawingTool.presentationHighlighter:
        return ToolType.pen; // Lasso/Laser/PresentationHighlighter don't draw strokes
      case DrawingTool.shapeLine:
      case DrawingTool.shapeRectangle:
      case DrawingTool.shapeCircle:
      case DrawingTool.shapeArrow:
        return ToolType.pen; // Shapes use pen-style strokes
    }
  }

  void _updateUndoRedoState() {
    final canvasState = _canvasKey.currentState;
    if (canvasState != null) {
      // ValueNotifier 사용으로 setState 없이 undo/redo 버튼만 업데이트
      _canUndoNotifier.value = canvasState.canUndo;
      _canRedoNotifier.value = canvasState.canRedo;
    }
  }

  Future<void> _saveNote() async {
    if (_currentNote == null) return;

    // Save current page strokes first
    _saveCurrentPageStrokes();

    await _storageService.saveNote(_currentNote!);

    setState(() => _hasChanges = false);
  }

  /// 즐겨찾기 토글
  Future<void> _toggleFavorite() async {
    if (_currentNote == null) return;

    // 로컬 상태 먼저 업데이트 (빠른 UI 반응)
    setState(() {
      _currentNote = _currentNote!.copyWith(
        isFavorite: !_currentNote!.isFavorite,
      );
    });

    // 저장소에도 저장
    await _storageService.saveNote(_currentNote!);
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
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 드래그 핸들
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // 내보내기 섹션
                _buildMenuSection('내보내기', Icons.upload_outlined, [
                  _buildMenuItem(Icons.image, '이미지 (PNG)', () {
                    Navigator.pop(context);
                    _showExportImageDialog();
                  }),
                  _buildMenuItem(Icons.picture_as_pdf, 'PDF', () {
                    Navigator.pop(context);
                    _exportToPdf();
                  }),
                  _buildMenuItem(Icons.share, '공유', () {
                    Navigator.pop(context);
                    _shareNote();
                  }),
                ]),

                const Divider(height: 24),

                // 노트 관리 섹션
                _buildMenuSection('노트 관리', Icons.note_outlined, [
                  _buildMenuItem(Icons.info_outline, '노트 정보', () {
                    Navigator.pop(context);
                    _showNoteInfo();
                  }),
                  _buildMenuItem(
                    Icons.label,
                    '태그 관리',
                    () {
                      Navigator.pop(context);
                      _showTagManagementDialog();
                    },
                    subtitle: _currentNote?.tags.isEmpty == true
                        ? '태그 없음'
                        : _currentNote!.tags.join(', '),
                  ),
                ]),

                const Divider(height: 24),

                // 설정 섹션
                _buildMenuSection('설정', Icons.settings_outlined, [
                  _buildMenuItem(
                    Icons.auto_fix_high,
                    '필기 보정',
                    () {
                      Navigator.pop(context);
                      _showSmoothingDialog();
                    },
                    subtitle: _getSmoothingLevelText(_smoothingLevel),
                  ),
                  _buildMenuItem(Icons.settings, '앱 설정', () {
                    Navigator.pop(context);
                    _openSettings();
                  }),
                ]),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 메뉴 섹션 헤더 빌드
  Widget _buildMenuSection(String title, IconData icon, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        Row(
          children: items.map((item) => Expanded(child: item)).toList(),
        ),
      ],
    );
  }

  /// 메뉴 아이템 빌드 (카드 스타일)
  Widget _buildMenuItem(IconData icon, String label, VoidCallback onTap, {String? subtitle}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle,
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SettingsPage(),
      ),
    );
    // Reload settings when returning from settings page
    if (mounted) {
      setState(() {
        _loadSettings();
      });
    }
  }

  /// 태그 관리 다이얼로그 표시
  void _showTagManagementDialog() {
    if (_currentNote == null) return;

    final tagController = TextEditingController();
    List<String> currentTags = List.from(_currentNote!.tags);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('태그 관리'),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 태그 입력 필드
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: tagController,
                        decoration: const InputDecoration(
                          hintText: '새 태그 입력',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (value) async {
                          if (value.trim().isNotEmpty) {
                            final normalizedTag = value.trim().toLowerCase();
                            if (!currentTags.contains(normalizedTag)) {
                              setDialogState(() {
                                currentTags.add(normalizedTag);
                              });
                              await _storageService.addTag(_currentNote!.id, normalizedTag);
                              _currentNote = await _storageService.loadNote(_currentNote!.id);
                              tagController.clear();
                              setState(() {});
                            }
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () async {
                        final value = tagController.text;
                        if (value.trim().isNotEmpty) {
                          final normalizedTag = value.trim().toLowerCase();
                          if (!currentTags.contains(normalizedTag)) {
                            setDialogState(() {
                              currentTags.add(normalizedTag);
                            });
                            await _storageService.addTag(_currentNote!.id, normalizedTag);
                            _currentNote = await _storageService.loadNote(_currentNote!.id);
                            tagController.clear();
                            setState(() {});
                          }
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 현재 태그 목록
                const Text('현재 태그:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (currentTags.isEmpty)
                  Text('태그 없음', style: TextStyle(color: Colors.grey[500]))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: currentTags.map((tag) {
                      return Chip(
                        label: Text(tag),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () async {
                          setDialogState(() {
                            currentTags.remove(tag);
                          });
                          await _storageService.removeTag(_currentNote!.id, tag);
                          _currentNote = await _storageService.loadNote(_currentNote!.id);
                          setState(() {});
                        },
                      );
                    }).toList(),
                  ),

                const SizedBox(height: 16),

                // 자주 사용하는 태그 추천
                FutureBuilder<List<String>>(
                  future: _storageService.getAllTags(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    final allTags = snapshot.data!
                        .where((t) => !currentTags.contains(t))
                        .take(5)
                        .toList();
                    if (allTags.isEmpty) return const SizedBox.shrink();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('추천 태그:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: allTags.map((tag) {
                            return ActionChip(
                              label: Text(tag),
                              onPressed: () async {
                                setDialogState(() {
                                  currentTags.add(tag);
                                });
                                await _storageService.addTag(_currentNote!.id, tag);
                                _currentNote = await _storageService.loadNote(_currentNote!.id);
                                setState(() {});
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
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
    } catch (e) {
      debugPrint('이미지 삽입 실패: $e');
    }
  }

  /// 배경 이미지 선택 (Canva 등에서 내보낸 이미지를 노트 템플릿으로 사용)
  Future<void> _selectBackgroundImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile == null) return;

      // Copy image to app's backgrounds directory for persistence
      final appDir = await getApplicationDocumentsDirectory();
      final backgroundsDir = Directory('${appDir.path}${Platform.pathSeparator}Winote${Platform.pathSeparator}backgrounds');
      if (!await backgroundsDir.exists()) {
        await backgroundsDir.create(recursive: true);
      }

      final fileName = '${DateTime.now().millisecondsSinceEpoch}${path.extension(pickedFile.path)}';
      final savedPath = '${backgroundsDir.path}${Platform.pathSeparator}$fileName';

      await File(pickedFile.path).copy(savedPath);

      // 배경 이미지 설정 및 템플릿을 customImage로 변경
      // 기존 템플릿이 있으면 overlayTemplate으로 보존 (배경 이미지 위에 줄/격자/점 표시)
      setState(() {
        // 기존 템플릿이 blank나 customImage가 아니면 오버레이로 보존
        if (_currentTemplate != PageTemplate.blank && _currentTemplate != PageTemplate.customImage) {
          _overlayTemplate = _currentTemplate;
        }
        _backgroundImagePath = savedPath;
        _currentTemplate = PageTemplate.customImage;
        _hasChanges = true;
      });

      _scheduleAutoSave();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('배경 이미지가 설정되었습니다'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      debugPrint('배경 이미지 선택 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('배경 이미지 선택 실패: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 배경 이미지 제거
  void _clearBackgroundImage() {
    setState(() {
      _backgroundImagePath = null;
      // overlayTemplate이 있으면 그것을 기본 템플릿으로 복원, 없으면 grid
      _currentTemplate = _overlayTemplate ?? PageTemplate.grid;
      _overlayTemplate = null;
      _hasChanges = true;
    });
    _scheduleAutoSave();
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

  void _showExportImageDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이미지로 내보내기'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('PNG (투명 배경 지원)'),
              subtitle: const Text('고품질, 용량 큼'),
              onTap: () {
                Navigator.pop(context);
                _exportAsImage('png');
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('JPG (흰 배경)'),
              subtitle: const Text('작은 용량'),
              onTap: () {
                Navigator.pop(context);
                _exportAsImage('jpg');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportAsImage(String format) async {
    // Save current page first
    _saveCurrentPageStrokes();

    final allStrokes = _currentNote?.strokes ?? [];
    if (allStrokes.isEmpty) {
      return;
    }

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text('${format.toUpperCase()} 생성 중...'),
          ],
        ),
      ),
    );

    try {
      // Get canvas size from render box
      final renderBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
      final canvasSize = renderBox?.size ?? const Size(800, 600);

      final imageService = ImageExportService.instance;
      String? filePath;

      if (format == 'png') {
        filePath = await imageService.exportAsPng(
          strokes: allStrokes,
          canvasSize: canvasSize,
          title: _currentNote?.title ?? '새 노트',
        );
      } else {
        filePath = await imageService.exportAsJpg(
          strokes: allStrokes,
          canvasSize: canvasSize,
          title: _currentNote?.title ?? '새 노트',
        );
      }

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      if (filePath != null) {
        // Show success dialog with options
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('${format.toUpperCase()} 내보내기 완료'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('이미지 파일이 생성되었습니다.'),
                  const SizedBox(height: 8),
                  Text(
                    filePath!,
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
                    // Open the image file
                    final uri = Uri.file(filePath!);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                  child: const Text('열기'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    // Open the folder
                    final folder = filePath!.substring(0, filePath!.lastIndexOf('\\'));
                    final uri = Uri.file(folder);
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
        debugPrint('이미지 내보내기 실패');
      }
    } catch (e) {
      // Close loading dialog on error
      if (mounted) Navigator.pop(context);
      debugPrint('이미지 내보내기 오류: $e');
    }
  }

  /// 표 삽입 다이얼로그
  void _showInsertTableDialog() {
    int rows = 3;
    int columns = 3;
    double cellWidth = 80.0;
    double cellHeight = 40.0;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('표 삽입'),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 행 수 설정
                Row(
                  children: [
                    const Text('행 수:'),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: rows > 1
                          ? () => setDialogState(() => rows--)
                          : null,
                    ),
                    Text('$rows', style: const TextStyle(fontSize: 18)),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: rows < 20
                          ? () => setDialogState(() => rows++)
                          : null,
                    ),
                  ],
                ),
                // 열 수 설정
                Row(
                  children: [
                    const Text('열 수:'),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: columns > 1
                          ? () => setDialogState(() => columns--)
                          : null,
                    ),
                    Text('$columns', style: const TextStyle(fontSize: 18)),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: columns < 10
                          ? () => setDialogState(() => columns++)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 셀 크기 설정
                const Text('셀 크기', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('너비:'),
                    Expanded(
                      child: Slider(
                        value: cellWidth,
                        min: 40,
                        max: 150,
                        divisions: 22,
                        label: '${cellWidth.round()}',
                        onChanged: (value) => setDialogState(() => cellWidth = value),
                      ),
                    ),
                    Text('${cellWidth.round()}'),
                  ],
                ),
                Row(
                  children: [
                    const Text('높이:'),
                    Expanded(
                      child: Slider(
                        value: cellHeight,
                        min: 20,
                        max: 80,
                        divisions: 12,
                        label: '${cellHeight.round()}',
                        onChanged: (value) => setDialogState(() => cellHeight = value),
                      ),
                    ),
                    Text('${cellHeight.round()}'),
                  ],
                ),
                const SizedBox(height: 16),
                // 미리보기
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '표 크기: ${(columns * cellWidth).round()} x ${(rows * cellHeight).round()} px',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _insertTable(rows, columns, cellWidth, cellHeight);
              },
              child: const Text('삽입'),
            ),
          ],
        ),
      ),
    );
  }

  /// 표를 CanvasTable로 캔버스에 삽입 (이동 가능)
  void _insertTable(int rows, int columns, double cellWidth, double cellHeight) {
    // 캔버스 중앙에 표 배치
    final renderBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    final canvasSize = renderBox?.size ?? const Size(800, 600);

    final tableWidth = columns * cellWidth;
    final tableHeight = rows * cellHeight;

    // 캔버스 중앙에서 시작
    final startX = (canvasSize.width - tableWidth) / 2;
    final startY = (canvasSize.height - tableHeight) / 2;

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // CanvasTable 생성
    final table = CanvasTable(
      id: 'table_$timestamp',
      position: Offset(startX, startY),
      rows: rows,
      columns: columns,
      cellWidth: cellWidth,
      cellHeight: cellHeight,
      borderColor: _currentColor,
      borderWidth: 1.5,
      timestamp: timestamp,
    );

    // 캔버스에 표 추가
    _canvasKey.currentState?.addTable(table);

    setState(() => _hasChanges = true);
    _updateUndoRedoState();
  }

  Future<void> _exportToPdf() async {
    // 먼저 현재 캔버스 상태를 노트에 동기화
    _saveCurrentPageStrokes();

    // 캔버스에서 스트로크 가져오기 시도, 실패하면 노트에서 가져오기
    List<Stroke> currentStrokes = _canvasKey.currentState?.strokes ?? [];

    // 캔버스 스트로크가 비어있으면 노트에서 가져오기 (fallback)
    if (currentStrokes.isEmpty && _currentNote != null) {
      currentStrokes = _currentNote!.strokes;
    }

    if (currentStrokes.isEmpty) {
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
        strokes: currentStrokes,
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
        debugPrint('PDF 생성 실패');
      }
    } catch (e) {
      // Close loading dialog if still open
      if (mounted) Navigator.pop(context);
      debugPrint('PDF 생성 오류: $e');
    }
  }

  /// PDF 배경 위젯 빌드
  Widget _buildPdfBackground() {
    final pdfShape = _getCurrentPagePdfBackground();
    if (pdfShape == null || pdfShape.pdfPath == null) {
      return const SizedBox.shrink();
    }

    final pdfFile = File(pdfShape.pdfPath!);
    if (!pdfFile.existsSync()) {
      debugPrint('[EditorPage] PDF 파일을 찾을 수 없습니다: ${pdfShape.pdfPath}');
      return const SizedBox.shrink();
    }

    final targetPdfPage = pdfShape.pdfPageIndex ?? 0;

    debugPrint('[EditorPage] PDF 배경 빌드: 노트페이지=$_currentPageIndex, PDF페이지=${targetPdfPage + 1}');

    // 페이지마다 고유한 Key를 사용하여 PDF 뷰어를 완전히 새로 생성
    // Key에 targetPdfPage를 포함하여 PDF 페이지가 바뀔 때마다 위젯 재생성
    return IgnorePointer(
      // PDF 뷰어 터치 이벤트 비활성화 (캔버스 위에서 그리기 가능하게)
      ignoring: true,
      child: SfPdfViewer.file(
        pdfFile,
        key: ValueKey('pdf_viewer_page_$targetPdfPage'),
        initialPageNumber: targetPdfPage + 1, // PDF 페이지는 1부터 시작
        canShowScrollHead: false,
        canShowScrollStatus: false,
        canShowPaginationDialog: false,
        enableDoubleTapZooming: false,
        enableTextSelection: false,
        pageLayoutMode: PdfPageLayoutMode.single,
        scrollDirection: PdfScrollDirection.horizontal,
        interactionMode: PdfInteractionMode.pan,
        onDocumentLoaded: (details) {
          debugPrint('[EditorPage] PDF 로드 완료: 총 ${details.document.pages.count}페이지, 현재 표시: ${targetPdfPage + 1}');
        },
      ),
    );
  }

  /// 노트 공유 (.wnote 파일로 공유)
  Future<void> _shareNote() async {
    if (_currentNote == null) return;

    // 현재 페이지 저장 후 공유
    _saveCurrentPageStrokes();
    await _storageService.saveNote(_currentNote!);

    // 로딩 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('공유 준비 중...'),
          ],
        ),
      ),
    );

    try {
      final success = await BackupService.instance.shareNote(_currentNote!);

      // 로딩 닫기
      if (mounted) Navigator.pop(context);

      if (!success) {
        debugPrint('공유에 실패했습니다');
      }
    } catch (e) {
      // 로딩 닫기
      if (mounted) Navigator.pop(context);
      debugPrint('공유 오류: $e');
    }
  }
}

/// 페이지 썸네일을 그리는 CustomPainter
class _PageThumbnailPainter extends CustomPainter {
  final List<Stroke> strokes;

  _PageThumbnailPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;

    // 모든 스트로크의 바운딩 박스 계산
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
    const padding = 10.0;
    minX -= padding;
    minY -= padding;
    maxX += padding;
    maxY += padding;

    // 썸네일에 맞게 스케일 계산
    final contentWidth = maxX - minX;
    final contentHeight = maxY - minY;

    if (contentWidth <= 0 || contentHeight <= 0) return;

    final scaleX = size.width / contentWidth;
    final scaleY = size.height / contentHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    // 콘텐츠 중앙 정렬
    final offsetX = (size.width - contentWidth * scale) / 2 - minX * scale;
    final offsetY = (size.height - contentHeight * scale) / 2 - minY * scale;

    // 각 스트로크 그리기
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;

      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = (stroke.width * scale).clamp(0.5, 3.0)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (stroke.points.length == 1) {
        // 단일 포인트 - 원으로 그리기
        final p = stroke.points.first;
        canvas.drawCircle(
          Offset(p.x * scale + offsetX, p.y * scale + offsetY),
          paint.strokeWidth / 2,
          paint,
        );
      } else {
        // 여러 포인트 - 경로로 그리기
        final path = Path();
        final first = stroke.points.first;
        path.moveTo(first.x * scale + offsetX, first.y * scale + offsetY);

        for (int i = 1; i < stroke.points.length; i++) {
          final p = stroke.points[i];
          path.lineTo(p.x * scale + offsetX, p.y * scale + offsetY);
        }

        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PageThumbnailPainter oldDelegate) {
    return strokes.length != oldDelegate.strokes.length;
  }
}

// 키보드 단축키용 Intent 클래스들
class UndoIntent extends Intent {
  const UndoIntent();
}

class RedoIntent extends Intent {
  const RedoIntent();
}

class SaveIntent extends Intent {
  const SaveIntent();
}
