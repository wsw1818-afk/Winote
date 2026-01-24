import 'package:flutter/material.dart';
import '../../../core/providers/drawing_state.dart';
import '../../../core/services/settings_service.dart';

/// Quick toolbar for tool selection and fast access
/// (실행취소/다시실행/색상/굵기 슬라이더는 DrawingToolbar에서 담당)
class QuickToolbar extends StatefulWidget {
  final DrawingTool currentTool;
  final Color currentColor;
  final Color highlighterColor; // 형광펜 전용 색상 (별도 저장)
  final double currentWidth;
  final double highlighterWidth; // 형광펜 전용 굵기 (별도 저장)
  final double eraserWidth;
  final double highlighterOpacity; // 형광펜 투명도 (0.0 ~ 1.0)
  final PageTemplate currentTemplate;
  final void Function(DrawingTool) onToolChanged;
  final void Function(Color) onColorChanged;
  final void Function(Color) onHighlighterColorChanged; // 형광펜 색상 콜백
  final void Function(double) onWidthChanged;
  final void Function(double) onHighlighterWidthChanged; // 형광펜 굵기 콜백
  final void Function(double) onEraserWidthChanged;
  final void Function(double) onHighlighterOpacityChanged; // 형광펜 투명도 콜백
  final void Function(PageTemplate) onTemplateChanged;
  // Lasso selection callbacks
  final bool hasSelection;
  final VoidCallback? onCopySelection;
  final VoidCallback? onDeleteSelection;
  final VoidCallback? onClearSelection;
  // Insert callbacks
  final VoidCallback? onInsertImage;
  final VoidCallback? onInsertText;
  final VoidCallback? onInsertTable;
  // Background image callbacks (커스텀 배경 이미지)
  final VoidCallback? onSelectBackgroundImage;
  final VoidCallback? onClearBackgroundImage;
  final bool hasBackgroundImage;
  final PageTemplate? overlayTemplate; // 배경 이미지 위에 표시되는 템플릿
  // Laser pointer color
  final Color laserPointerColor;
  final void Function(Color)? onLaserPointerColorChanged;
  // Presentation highlighter fade mode
  final bool presentationHighlighterFadeEnabled;
  final void Function(bool)? onPresentationHighlighterFadeChanged;
  // Presentation highlighter fade speed
  final double presentationHighlighterFadeSpeed;
  final void Function(double)? onPresentationHighlighterFadeSpeedChanged;
  // 패널 상태 콜백 (캔버스 터치 시 패널 닫기 위해)
  // 패널이 열릴 때 닫기 콜백을 부모에게 전달
  final void Function(VoidCallback closeCallback)? onPanelOpened;
  // Undo/Redo/Save/Clear 콜백
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onSave;
  final VoidCallback? onClear;
  final bool canUndo;
  final bool canRedo;
  final bool hasChanges; // 저장되지 않은 변경사항 있음

  const QuickToolbar({
    super.key,
    required this.currentTool,
    required this.currentColor,
    required this.highlighterColor,
    required this.currentWidth,
    required this.highlighterWidth,
    this.eraserWidth = 20.0,
    this.highlighterOpacity = 0.4,
    required this.currentTemplate,
    required this.onToolChanged,
    required this.onColorChanged,
    required this.onHighlighterColorChanged,
    required this.onWidthChanged,
    required this.onHighlighterWidthChanged,
    required this.onEraserWidthChanged,
    required this.onHighlighterOpacityChanged,
    required this.onTemplateChanged,
    this.hasSelection = false,
    this.onCopySelection,
    this.onDeleteSelection,
    this.onClearSelection,
    this.onInsertImage,
    this.onInsertText,
    this.onInsertTable,
    this.onSelectBackgroundImage,
    this.onClearBackgroundImage,
    this.hasBackgroundImage = false,
    this.overlayTemplate,
    this.laserPointerColor = Colors.red,
    this.onLaserPointerColorChanged,
    this.presentationHighlighterFadeEnabled = true,
    this.onPresentationHighlighterFadeChanged,
    this.presentationHighlighterFadeSpeed = 1.0,
    this.onPresentationHighlighterFadeSpeedChanged,
    this.onPanelOpened,
    this.onUndo,
    this.onRedo,
    this.onSave,
    this.onClear,
    this.canUndo = false,
    this.canRedo = false,
    this.hasChanges = false,
  });

  // Preset widths for pen (다양한 크기 프리셋)
  static const List<double> penWidthPresets = [0.5, 1.0, 2.0, 3.0, 5.0, 8.0, 12.0, 20.0];
  // Preset widths for eraser
  static const List<double> eraserWidths = [10.0, 20.0, 40.0, 60.0, 80.0, 150.0];
  // Preset widths for highlighter (더 두꺼운 크기)
  static const List<double> highlighterWidthPresets = [10.0, 15.0, 20.0, 25.0, 30.0, 40.0, 50.0];
  // Preset opacities for highlighter (투명도 프리셋)
  static const List<double> highlighterOpacityPresets = [0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8];
  // Preset colors for highlighter (반투명 형광색) - 10개 확장
  static const List<Color> highlighterColors = [
    // 1열 (5개)
    Color(0xFFFFEB3B), // Yellow
    Color(0xFFFF80AB), // Pink
    Color(0xFF80DEEA), // Cyan/Light Blue
    Color(0xFFA5D6A7), // Light Green
    Color(0xFFFFCC80), // Orange
    // 2열 (5개)
    Color(0xFFCE93D8), // Purple/Lavender
    Color(0xFFEF9A9A), // Light Red
    Color(0xFF90CAF9), // Light Blue
    Color(0xFFE6EE9C), // Lime
    Color(0xFFB0BEC5), // Blue Gray
  ];
  // Preset colors for laser pointer
  static const List<Color> laserPointerColors = [
    Color(0xFFFF0000), // Red
    Color(0xFF00FF00), // Green
    Color(0xFF0000FF), // Blue
    Color(0xFFFF00FF), // Magenta
    Color(0xFFFFFF00), // Yellow
    Color(0xFF00FFFF), // Cyan
    Color(0xFFFF8000), // Orange
    Color(0xFFFFFFFF), // White
  ];

  @override
  State<QuickToolbar> createState() => _QuickToolbarState();
}

class _QuickToolbarState extends State<QuickToolbar> {
  final SettingsService _settings = SettingsService.instance;
  List<Color> _favoriteColors = [];

  // Overlay 관리 (패널이 열려있는 동안 캔버스 터치 허용)
  OverlayEntry? _currentOverlay;

  @override
  void dispose() {
    _closeOverlay();
    super.dispose();
  }

  void _closeOverlay() {
    _currentOverlay?.remove();
    _currentOverlay = null;
  }

  /// 성능 최적화: 공통 Overlay 표시 헬퍼 메소드
  /// RenderBox 계산 로직 통합
  Offset? _getButtonPosition(BuildContext context) {
    final renderObject = context.findRenderObject();
    if (renderObject == null || renderObject is! RenderBox) return null;

    final overlayContext = Overlay.of(context).context;
    final overlayRenderObject = overlayContext.findRenderObject();
    if (overlayRenderObject == null || overlayRenderObject is! RenderBox) return null;

    return renderObject.localToGlobal(Offset.zero, ancestor: overlayRenderObject);
  }

  /// 공통 Overlay 생성 및 표시
  void _showPanelOverlay(BuildContext context, OverlayEntry Function(Offset position) builder) {
    // 이미 열려있으면 닫기
    if (_currentOverlay != null) {
      _closeOverlay();
      return;
    }

    final position = _getButtonPosition(context);
    if (position == null) return;

    _currentOverlay = builder(position);
    Overlay.of(context).insert(_currentOverlay!);

    // 부모에게 패널이 열렸음을 알리고 닫기 콜백 전달
    widget.onPanelOpened?.call(_closeOverlay);
  }

  // 기본 프리셋 색상 (초기값, 설정 로드 전) - 10개 (형광펜과 동일 레이아웃)
  static const List<Color> _defaultColors = [
    // 1열 (5개)
    Colors.black,
    Color(0xFF424242), // Dark Gray
    Color(0xFF1976D2), // Blue
    Color(0xFF388E3C), // Green
    Color(0xFFD32F2F), // Red
    // 2열 (5개)
    Colors.white,
    Color(0xFF795548), // Brown
    Color(0xFFF57C00), // Orange
    Color(0xFF7B1FA2), // Purple
    Color(0xFF3F51B5), // Indigo
  ];

  @override
  void initState() {
    super.initState();
    _loadFavoriteColors();
  }

  void _loadFavoriteColors() {
    setState(() {
      _favoriteColors = _settings.favoriteColors;
      if (_favoriteColors.isEmpty) {
        _favoriteColors = _defaultColors;
      }
    });
  }

  Future<void> _addColorToFavorites(Color color) async {
    await _settings.addFavoriteColor(color);
    _loadFavoriteColors();
  }

  Future<void> _removeColorFromFavorites(Color color) async {
    await _settings.removeFavoriteColor(color);
    _loadFavoriteColors();
  }

  bool get _isShapeTool {
    return widget.currentTool == DrawingTool.shapeLine ||
        widget.currentTool == DrawingTool.shapeRectangle ||
        widget.currentTool == DrawingTool.shapeCircle ||
        widget.currentTool == DrawingTool.shapeArrow;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Undo/Redo buttons
          _buildIconButton(
            Icons.undo,
            widget.canUndo ? widget.onUndo : null,
            tooltip: '실행취소',
            enabled: widget.canUndo,
          ),
          _buildIconButton(
            Icons.redo,
            widget.canRedo ? widget.onRedo : null,
            tooltip: '다시실행',
            enabled: widget.canRedo,
          ),
          _buildDivider(),
          // Pen presets (펜 프리셋)
          _buildPenPresetsButton(context),
          _buildDivider(),
          // Drawing tools with dropdown menus
          _buildPenToolButton(context), // 펜 (색상 + 굵기)
          _buildHighlighterToolButton(context), // 형광펜 (색상 + 굵기 + 투명도)
          _buildEraserToolButton(context), // 지우개 (굵기 + 영역 지우개)
          _buildToolButton(DrawingTool.lasso, Icons.gesture, '올가미'),
          _buildLaserPointerToolButton(context),
          _buildPresentationHighlighterToolButton(context),
          _buildShapeToolButton(context),
          _buildDivider(),

          // Selection actions (only show when has selection)
          if (widget.hasSelection) ...[
            _buildIconButton(
              Icons.copy,
              widget.onCopySelection,
              tooltip: '복사',
            ),
            _buildIconButton(
              Icons.delete_outline,
              widget.onDeleteSelection,
              tooltip: '삭제',
            ),
            _buildIconButton(
              Icons.close,
              widget.onClearSelection,
              tooltip: '선택 해제',
            ),
            _buildDivider(),
          ],

          // Template selector
          _buildTemplateButton(context),
          _buildDivider(),

          // Insert menu
          _buildInsertButton(context),
          _buildDivider(),
          // Save button (shows indicator when has unsaved changes)
          _buildSaveButton(),
          // Clear/Delete all button
          _buildIconButton(
            Icons.delete_sweep,
            widget.onClear,
            tooltip: '전체삭제',
          ),
        ],
      ),
    );
  }

  /// 저장 버튼 (변경사항 있으면 강조 표시)
  Widget _buildSaveButton() {
    return Tooltip(
      message: widget.hasChanges ? '저장 (변경사항 있음)' : '저장됨',
      child: InkWell(
        onTap: widget.hasChanges ? widget.onSave : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: widget.hasChanges ? Colors.orange.withOpacity(0.1) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Stack(
            children: [
              Icon(
                widget.hasChanges ? Icons.save : Icons.check_circle_outline,
                size: 20,
                color: widget.hasChanges ? Colors.orange : Colors.green,
              ),
              if (widget.hasChanges)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 색상 관리 버튼 (현재 색상 추가 + 색상 목록 관리)
  Widget _buildColorManagerButton(BuildContext context) {
    final isCurrentColorInFavorites = _favoriteColors.any(
      (c) => c.value == widget.currentColor.value,
    );

    return Tooltip(
      message: '색상 관리',
      child: PopupMenuButton<String>(
        tooltip: '', // 기본 "Show menu" 툴팁 비활성화
        offset: const Offset(0, -200),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: const Icon(Icons.add, size: 16, color: Colors.grey),
        ),
        itemBuilder: (context) => [
          // 현재 색상 추가/제거
          PopupMenuItem<String>(
            value: 'toggle_current',
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: widget.currentColor,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                ),
                const SizedBox(width: 12),
                Text(isCurrentColorInFavorites ? '현재 색상 제거' : '현재 색상 추가'),
                const Spacer(),
                Icon(
                  isCurrentColorInFavorites ? Icons.remove : Icons.add,
                  size: 18,
                  color: isCurrentColorInFavorites ? Colors.red : Colors.blue,
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          // 즐겨찾기 색상 목록 표시
          PopupMenuItem<String>(
            enabled: false,
            child: Text(
              '즐겨찾기 색상 (${_favoriteColors.length}개)',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // 각 색상을 롱프레스로 제거 가능하도록 표시
          ..._favoriteColors.asMap().entries.map((entry) {
            final index = entry.key;
            final color = entry.value;
            return PopupMenuItem<String>(
              value: 'remove_$index',
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(_getColorName(color)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.red),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: null, // PopupMenuItem이 처리
                  ),
                ],
              ),
            );
          }),
        ],
        onSelected: (value) async {
          if (value == 'toggle_current') {
            if (isCurrentColorInFavorites) {
              await _removeColorFromFavorites(widget.currentColor);
            } else {
              await _addColorToFavorites(widget.currentColor);
            }
          } else if (value.startsWith('remove_')) {
            final index = int.parse(value.substring(7));
            if (index < _favoriteColors.length) {
              await _removeColorFromFavorites(_favoriteColors[index]);
            }
          }
        },
      ),
    );
  }

  Widget _buildTemplateButton(BuildContext context) {
    // 배경 이미지가 있을 때는 overlayTemplate 아이콘 표시, 없으면 currentTemplate 표시
    final displayTemplate = widget.hasBackgroundImage
        ? (widget.overlayTemplate ?? PageTemplate.blank) // 오버레이 없으면 빈 페이지 아이콘
        : widget.currentTemplate;
    final hasOverlay = widget.hasBackgroundImage && widget.overlayTemplate != null;

    return Tooltip(
      message: widget.hasBackgroundImage ? '오버레이 템플릿 (배경 이미지 위에 표시)' : '페이지 템플릿',
      child: PopupMenuButton<PageTemplate>(
        tooltip: '', // 기본 "Show menu" 툴팁 비활성화
        onSelected: widget.onTemplateChanged,
        offset: const Offset(0, -200),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: hasOverlay ? Colors.green.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border: widget.hasBackgroundImage
                ? Border.all(color: hasOverlay ? Colors.green : Colors.orange, width: 1.5)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.hasBackgroundImage) ...[
                const Icon(Icons.wallpaper, size: 14, color: Colors.orange),
                const SizedBox(width: 2),
                const Text('+', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 2),
              ],
              Icon(_getTemplateIcon(displayTemplate), size: 20, color: hasOverlay ? Colors.green : Colors.blue),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_up, size: 16, color: Colors.blue),
            ],
          ),
        ),
        itemBuilder: (context) => [
          _buildTemplateMenuItem(PageTemplate.blank, Icons.crop_square, widget.hasBackgroundImage ? '오버레이 없음' : '빈 페이지'),
          _buildTemplateMenuItem(PageTemplate.lined, Icons.view_headline, '줄 노트'),
          _buildTemplateMenuItem(PageTemplate.grid, Icons.grid_4x4, '격자 노트'),
          _buildTemplateMenuItem(PageTemplate.dotted, Icons.more_horiz, '점 노트'),
          _buildTemplateMenuItem(PageTemplate.cornell, Icons.view_quilt, '코넬 노트'),
        ],
      ),
    );
  }

  Widget _buildInsertButton(BuildContext context) {
    return Tooltip(
      message: '삽입',
      child: PopupMenuButton<String>(
        tooltip: '', // 기본 "Show menu" 툴팁 비활성화
        onSelected: (value) {
          switch (value) {
            case 'image':
              widget.onInsertImage?.call();
              break;
            case 'text':
              widget.onInsertText?.call();
              break;
            case 'table':
              widget.onInsertTable?.call();
              break;
            case 'background':
              widget.onSelectBackgroundImage?.call();
              break;
            case 'clear_background':
              widget.onClearBackgroundImage?.call();
              break;
          }
        },
        offset: const Offset(0, -150),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_circle_outline, size: 20, color: Colors.green[700]),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_up, size: 16, color: Colors.green),
            ],
          ),
        ),
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'image',
            child: Row(
              children: [
                Icon(Icons.add_photo_alternate, size: 20),
                SizedBox(width: 12),
                Text('이미지'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'text',
            child: Row(
              children: [
                Icon(Icons.text_fields, size: 20),
                SizedBox(width: 12),
                Text('텍스트'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'table',
            child: Row(
              children: [
                Icon(Icons.table_chart, size: 20),
                SizedBox(width: 12),
                Text('표'),
              ],
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'background',
            child: Row(
              children: [
                Icon(Icons.wallpaper, size: 20, color: Colors.deepPurple),
                SizedBox(width: 12),
                Text('배경 이미지 (Canva 템플릿)'),
              ],
            ),
          ),
          if (widget.hasBackgroundImage)
            const PopupMenuItem(
              value: 'clear_background',
              child: Row(
                children: [
                  Icon(Icons.wallpaper_outlined, size: 20, color: Colors.grey),
                  SizedBox(width: 12),
                  Text('배경 이미지 제거'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  PopupMenuItem<PageTemplate> _buildTemplateMenuItem(
    PageTemplate template,
    IconData icon,
    String label,
  ) {
    final isSelected = widget.currentTemplate == template;
    return PopupMenuItem<PageTemplate>(
      value: template,
      child: Row(
        children: [
          Icon(icon, size: 20, color: isSelected ? Colors.blue : Colors.grey[700]),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.blue : Colors.grey[800],
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (isSelected) ...[
            const Spacer(),
            const Icon(Icons.check, size: 18, color: Colors.blue),
          ],
        ],
      ),
    );
  }

  IconData _getTemplateIcon(PageTemplate template) {
    switch (template) {
      case PageTemplate.blank:
        return Icons.crop_square;
      case PageTemplate.lined:
        return Icons.view_headline;
      case PageTemplate.grid:
        return Icons.grid_4x4;
      case PageTemplate.dotted:
        return Icons.more_horiz;
      case PageTemplate.cornell:
        return Icons.view_quilt;
      case PageTemplate.customImage:
        return Icons.wallpaper;
    }
  }

  IconData _getShapeIcon(DrawingTool tool) {
    switch (tool) {
      case DrawingTool.shapeLine:
        return Icons.show_chart;
      case DrawingTool.shapeRectangle:
        return Icons.crop_square;
      case DrawingTool.shapeCircle:
        return Icons.circle_outlined;
      case DrawingTool.shapeArrow:
        return Icons.arrow_forward;
      default:
        return Icons.category;
    }
  }

  String _getShapeTooltip(DrawingTool tool) {
    switch (tool) {
      case DrawingTool.shapeLine:
        return '직선';
      case DrawingTool.shapeRectangle:
        return '사각형';
      case DrawingTool.shapeCircle:
        return '원';
      case DrawingTool.shapeArrow:
        return '화살표';
      default:
        return '도형';
    }
  }

  /// 펜 프리셋 버튼 (저장된 펜 설정 빠른 적용)
  Widget _buildPenPresetsButton(BuildContext context) {
    return Tooltip(
      message: '펜 프리셋',
      child: InkWell(
        onTap: () => _showPenPresetsPanel(context),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.bookmarks, size: 20, color: Colors.blueGrey),
        ),
      ),
    );
  }

  void _showPenPresetsPanel(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final buttonPosition = button.localToGlobal(Offset.zero);

    _closeOverlay();

    final overlay = Overlay.of(context);
    _currentOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // 배경 탭 시 닫기
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeOverlay,
              behavior: HitTestBehavior.translucent,
              child: Container(color: Colors.transparent),
            ),
          ),
          // 프리셋 패널 (축소 버전)
          Positioned(
            left: buttonPosition.dx - 40,
            top: buttonPosition.dy + 40,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 220,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '펜 프리셋',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                        // 현재 펜 저장 버튼
                        TextButton.icon(
                          onPressed: () => _saveCurrentPenAsPreset(),
                          icon: const Icon(Icons.add, size: 12),
                          label: const Text('현재 펜 저장', style: TextStyle(fontSize: 10)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // 프리셋 목록
                    ..._settings.penPresets.asMap().entries.map((entry) {
                      final index = entry.key;
                      final preset = entry.value;
                      final color = Color(preset['color'] as int);
                      final width = (preset['width'] as num).toDouble();
                      final name = preset['name'] as String;
                      final toolType = preset['toolType'] as String? ?? 'pen';

                      return InkWell(
                        onTap: () {
                          // 프리셋 적용
                          if (toolType == 'highlighter') {
                            widget.onToolChanged(DrawingTool.highlighter);
                            widget.onHighlighterColorChanged(color);
                            widget.onHighlighterWidthChanged(width);
                          } else {
                            widget.onToolChanged(DrawingTool.pen);
                            widget.onColorChanged(color);
                            widget.onWidthChanged(width);
                          }
                          _closeOverlay();
                        },
                        onLongPress: () {
                          // 길게 눌러서 삭제
                          _showDeletePresetDialog(index, name);
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          margin: const EdgeInsets.only(bottom: 3),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Row(
                            children: [
                              // 색상 미리보기
                              Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: toolType == 'highlighter'
                                      ? color.withOpacity(0.4)
                                      : color,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // 이름
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                              // 굵기 미리보기
                              Container(
                                width: 30,
                                height: width.clamp(2.0, 14.0),
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(width / 2),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // 도구 타입 아이콘
                              Icon(
                                toolType == 'highlighter'
                                    ? Icons.brush
                                    : Icons.edit,
                                size: 12,
                                color: Colors.grey[500],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                    if (_settings.penPresets.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(10),
                        child: const Text(
                          '저장된 프리셋이 없습니다.\n"현재 펜 저장"을 눌러 추가하세요.',
                          style: TextStyle(color: Colors.grey, fontSize: 10),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const Divider(height: 10),
                    Text(
                      '💡 길게 눌러서 삭제 | 최대 5개',
                      style: TextStyle(color: Colors.grey[500], fontSize: 9),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(_currentOverlay!);
    widget.onPanelOpened?.call(_closeOverlay);
  }

  void _saveCurrentPenAsPreset() {
    final currentTool = widget.currentTool;
    String toolType = 'pen';
    Color color = widget.currentColor;
    double width = widget.currentWidth;

    if (currentTool == DrawingTool.highlighter) {
      toolType = 'highlighter';
      color = widget.highlighterColor;
      width = widget.highlighterWidth;
    }

    // 이름 입력 다이얼로그
    showDialog(
      context: context,
      builder: (dialogContext) {
        String presetName = toolType == 'highlighter' ? '형광펜' : '펜';
        return AlertDialog(
          title: const Text('프리셋 저장'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '프리셋 이름',
              hintText: '예: 검정 펜, 빨강 형광펜',
            ),
            onChanged: (value) => presetName = value,
            controller: TextEditingController(text: presetName),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _settings.addPenPreset({
                  'name': presetName,
                  'color': color.value,
                  'width': width,
                  'toolType': toolType,
                });
                Navigator.pop(dialogContext);
                _closeOverlay();
                // 패널 다시 열어서 업데이트된 목록 보여주기
                if (mounted) {
                  setState(() {});
                }
              },
              child: const Text('저장'),
            ),
          ],
        );
      },
    );
  }

  void _showDeletePresetDialog(int index, String name) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('프리셋 삭제'),
        content: Text('"$name" 프리셋을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _settings.removePenPreset(index);
              Navigator.pop(dialogContext);
              _closeOverlay();
              if (mounted) {
                setState(() {});
              }
            },
            child: const Text('삭제', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// 펜 도구 버튼 (색상 + 굵기 가로 패널)
  Widget _buildPenToolButton(BuildContext context) {
    final isSelected = widget.currentTool == DrawingTool.pen;

    return Tooltip(
      message: '펜',
      child: GestureDetector(
        onTap: () {
          widget.onToolChanged(DrawingTool.pen);
          _showPenPanel(context);
        },
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.withOpacity(0.1) : null,
            borderRadius: BorderRadius.circular(6),
            border: isSelected ? Border.all(color: Colors.blue, width: 1.5) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.edit,
                    size: 20,
                    color: isSelected ? Colors.blue : Colors.grey[700],
                  ),
                  // 현재 선택된 색상 표시
                  Positioned(
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 3,
                      decoration: BoxDecoration(
                        color: widget.currentColor,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ],
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: isSelected ? Colors.blue : Colors.grey[700],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 펜 설정 패널 표시 (Overlay 방식 - 캔버스 터치 허용)
  void _showPenPanel(BuildContext context) {
    _showPanelOverlay(context, (position) => OverlayEntry(
      builder: (_) => _PenPanelOverlay(
        buttonPosition: position,
        currentColor: widget.currentColor,
        currentWidth: widget.currentWidth,
        onColorChanged: widget.onColorChanged,
        onWidthChanged: widget.onWidthChanged,
        onClose: _closeOverlay,
        defaultColors: _defaultColors,
      ),
    ));
  }

  /// 형광펜 도구 버튼 (색상 + 굵기 + 투명도 가로 패널)
  Widget _buildHighlighterToolButton(BuildContext context) {
    final isSelected = widget.currentTool == DrawingTool.highlighter;
    // 항상 형광펜 전용 색상 사용 (펜 색상과 분리)
    final currentHighlighterColor = widget.highlighterColor;

    return Tooltip(
      message: '형광펜',
      child: GestureDetector(
        onTap: () {
          // 프레젠테이션 형광펜 사용 중이면 도구 변경하지 않고 패널만 표시
          // (색상/굵기/투명도 변경 시 프레젠테이션 형광펜 상태 유지)
          if (widget.currentTool != DrawingTool.presentationHighlighter) {
            widget.onToolChanged(DrawingTool.highlighter);
          }
          _showHighlighterPanel(context);
        },
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.withOpacity(0.1) : null,
            borderRadius: BorderRadius.circular(6),
            border: isSelected ? Border.all(color: Colors.blue, width: 1.5) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.brush,
                    size: 20,
                    color: isSelected ? Colors.blue : Colors.grey[700],
                  ),
                  Positioned(
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 3,
                      decoration: BoxDecoration(
                        color: currentHighlighterColor,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ],
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: isSelected ? Colors.blue : Colors.grey[700],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 형광펜 설정 패널 표시 (Overlay 방식 - 캔버스 터치 허용)
  void _showHighlighterPanel(BuildContext context) {
    _showPanelOverlay(context, (position) => OverlayEntry(
      builder: (_) => _HighlighterPanelOverlay(
        buttonPosition: position,
        currentColor: widget.highlighterColor,
        currentWidth: widget.highlighterWidth,
        currentOpacity: widget.highlighterOpacity,
        onColorChanged: widget.onHighlighterColorChanged,
        onWidthChanged: widget.onHighlighterWidthChanged,
        onOpacityChanged: widget.onHighlighterOpacityChanged,
        onClose: _closeOverlay,
      ),
    ));
  }

  /// 지우개 도구 버튼 (굵기 가로 패널 + 영역 지우개 포함)
  Widget _buildEraserToolButton(BuildContext context) {
    final isEraserSelected = widget.currentTool == DrawingTool.eraser;
    final isAreaEraserSelected = widget.currentTool == DrawingTool.areaEraser;
    final isSelected = isEraserSelected || isAreaEraserSelected;
    final highlightColor = isAreaEraserSelected ? Colors.red : Colors.blue;

    return Tooltip(
      message: '지우개',
      child: GestureDetector(
        onTap: () {
          if (!isSelected) {
            widget.onToolChanged(DrawingTool.eraser);
          }
          _showEraserPanel(context);
        },
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isSelected ? highlightColor.withOpacity(0.1) : null,
            borderRadius: BorderRadius.circular(6),
            border: isSelected ? Border.all(color: highlightColor, width: 1.5) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    isAreaEraserSelected ? Icons.select_all : Icons.auto_fix_normal,
                    size: 20,
                    color: isSelected ? highlightColor : Colors.grey[700],
                  ),
                  if (!isAreaEraserSelected)
                    Positioned(
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                ],
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: isSelected ? highlightColor : Colors.grey[700],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 지우개 설정 패널 표시 (Overlay 방식 - 캔버스 터치 허용)
  void _showEraserPanel(BuildContext context) {
    _showPanelOverlay(context, (position) => OverlayEntry(
      builder: (_) => _EraserPanelOverlay(
        buttonPosition: position,
        currentWidth: widget.eraserWidth,
        onWidthChanged: widget.onEraserWidthChanged,
        onClose: _closeOverlay,
        currentTool: widget.currentTool,
        onToolChanged: widget.onToolChanged,
      ),
    ));
  }

  /// 영역 지우개 도구 버튼
  Widget _buildAreaEraserToolButton() {
    final isSelected = widget.currentTool == DrawingTool.areaEraser;

    return Tooltip(
      message: '영역 지우개\n(선택 영역의 스트로크 전체 삭제)',
      child: GestureDetector(
        onTap: () {
          widget.onToolChanged(DrawingTool.areaEraser);
        },
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.red.withOpacity(0.1) : null,
            borderRadius: BorderRadius.circular(6),
            border: isSelected ? Border.all(color: Colors.red, width: 1.5) : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.select_all,
                size: 20,
                color: isSelected ? Colors.red : Colors.grey[700],
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 6,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShapeToolButton(BuildContext context) {
    final isSelected = _isShapeTool;
    final currentShapeIcon = isSelected ? _getShapeIcon(widget.currentTool) : Icons.category;

    return Tooltip(
      message: '도형 삽입',
      child: PopupMenuButton<DrawingTool>(
        tooltip: '', // 기본 "Show menu" 툴팁 비활성화
        onSelected: widget.onToolChanged,
        offset: const Offset(0, -180),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.withOpacity(0.1) : null,
            borderRadius: BorderRadius.circular(6),
            border: isSelected ? Border.all(color: Colors.blue, width: 1.5) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                currentShapeIcon,
                size: 20,
                color: isSelected ? Colors.blue : Colors.grey[700],
              ),
              Icon(
                Icons.arrow_drop_up,
                size: 16,
                color: isSelected ? Colors.blue : Colors.grey[700],
              ),
            ],
          ),
        ),
        itemBuilder: (context) => [
          _buildShapeMenuItem(DrawingTool.shapeLine, Icons.show_chart, '직선'),
          _buildShapeMenuItem(DrawingTool.shapeRectangle, Icons.crop_square, '사각형'),
          _buildShapeMenuItem(DrawingTool.shapeCircle, Icons.circle_outlined, '원'),
          _buildShapeMenuItem(DrawingTool.shapeArrow, Icons.arrow_forward, '화살표'),
        ],
      ),
    );
  }

  PopupMenuItem<DrawingTool> _buildShapeMenuItem(
    DrawingTool tool,
    IconData icon,
    String label,
  ) {
    final isSelected = widget.currentTool == tool;
    return PopupMenuItem<DrawingTool>(
      value: tool,
      child: Row(
        children: [
          Icon(icon, size: 20, color: isSelected ? Colors.blue : Colors.grey[700]),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.blue : Colors.grey[800],
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (isSelected) ...[
            const Spacer(),
            const Icon(Icons.check, size: 18, color: Colors.blue),
          ],
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.grey[300],
    );
  }

  Widget _buildIconButton(
    IconData icon,
    VoidCallback? onPressed, {
    bool enabled = true,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 20,
            color: enabled ? Colors.grey[700] : Colors.grey[300],
          ),
        ),
      ),
    );
  }

  Widget _buildToolButton(DrawingTool tool, IconData icon, String tooltip) {
    final isSelected = widget.currentTool == tool;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => widget.onToolChanged(tool),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.withOpacity(0.1) : null,
            borderRadius: BorderRadius.circular(6),
            border: isSelected ? Border.all(color: Colors.blue, width: 1.5) : null,
          ),
          child: Icon(
            icon,
            size: 20,
            color: isSelected ? Colors.blue : Colors.grey[700],
          ),
        ),
      ),
    );
  }

  /// Build laser pointer tool button with color indicator and long press color picker
  Widget _buildLaserPointerToolButton(BuildContext context) {
    final isSelected = widget.currentTool == DrawingTool.laserPointer;
    final buttonKey = GlobalKey();

    return Tooltip(
      message: '레이저 포인터 (길게 눌러 색상 변경)',
      child: GestureDetector(
        onTap: () => widget.onToolChanged(DrawingTool.laserPointer),
        onLongPress: () {
          // Show laser pointer color picker popup
          final RenderBox button = buttonKey.currentContext!.findRenderObject() as RenderBox;
          final buttonPosition = button.localToGlobal(Offset.zero);
          final buttonSize = button.size;

          showDialog(
            context: context,
            barrierColor: Colors.transparent,
            builder: (context) => Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Positioned(
                  left: buttonPosition.dx - 50,
                  top: buttonPosition.dy + 40, // 툴바 아래로 팝업 표시
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '레이저 색상',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Color grid (2 rows of 4)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: QuickToolbar.laserPointerColors.take(4).map((color) {
                              final isColorSelected = widget.laserPointerColor.value == color.value;
                              return GestureDetector(
                                onTap: () {
                                  widget.onLaserPointerColorChanged?.call(color);
                                  Navigator.pop(context);
                                },
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  margin: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isColorSelected ? Colors.blue : (color == const Color(0xFFFFFFFF) ? Colors.grey[400]! : Colors.grey[300]!),
                                      width: isColorSelected ? 2.5 : 1,
                                    ),
                                  ),
                                  child: isColorSelected
                                      ? Icon(Icons.check, size: 16, color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white)
                                      : null,
                                ),
                              );
                            }).toList(),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: QuickToolbar.laserPointerColors.skip(4).map((color) {
                              final isColorSelected = widget.laserPointerColor.value == color.value;
                              return GestureDetector(
                                onTap: () {
                                  widget.onLaserPointerColorChanged?.call(color);
                                  Navigator.pop(context);
                                },
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  margin: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isColorSelected ? Colors.blue : (color == const Color(0xFFFFFFFF) ? Colors.grey[400]! : Colors.grey[300]!),
                                      width: isColorSelected ? 2.5 : 1,
                                    ),
                                  ),
                                  child: isColorSelected
                                      ? Icon(Icons.check, size: 16, color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white)
                                      : null,
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        child: Container(
          key: buttonKey,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.withOpacity(0.1) : null,
            borderRadius: BorderRadius.circular(6),
            border: isSelected ? Border.all(color: Colors.blue, width: 1.5) : null,
          ),
          child: Stack(
            children: [
              Icon(
                Icons.highlight_alt,
                size: 20,
                color: isSelected ? Colors.blue : Colors.grey[700],
              ),
              // Color indicator dot
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: widget.laserPointerColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build presentation highlighter tool button - tap toggles fade ON/OFF, long press shows speed panel
  Widget _buildPresentationHighlighterToolButton(BuildContext context) {
    final isSelected = widget.currentTool == DrawingTool.presentationHighlighter;

    // 속도에 따른 라벨
    String speedLabel = '';
    if (widget.presentationHighlighterFadeSpeed <= 0.1) {
      speedLabel = '느림';
    } else if (widget.presentationHighlighterFadeSpeed >= 2.0) {
      speedLabel = '빠름';
    } else {
      speedLabel = '보통';
    }

    return Tooltip(
      message: widget.presentationHighlighterFadeEnabled
          ? '프레젠테이션 형광펜 ON ($speedLabel) - 탭: ON/OFF, 길게 누름: 속도 조절'
          : '프레젠테이션 형광펜 OFF (저장됨) - 탭: ON/OFF',
      child: GestureDetector(
        onTap: () {
          // 이미 선택되어 있으면 ON/OFF 토글, 아니면 도구만 선택 (ON/OFF 상태 유지)
          if (isSelected) {
            widget.onPresentationHighlighterFadeChanged?.call(!widget.presentationHighlighterFadeEnabled);
          } else {
            widget.onToolChanged(DrawingTool.presentationHighlighter);
            // 도구 선택 시 기존 ON/OFF 상태 유지 (변경하지 않음)
          }
        },
        onLongPress: () {
          // 롱프레스: 속도 조절 패널 표시
          _showPresentationHighlighterSpeedPanel(context);
        },
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            // 선택 여부와 관계없이 ON/OFF 상태 표시
            // ON일 때 밝은 노란색 배경, OFF일 때 회색 배경
            color: widget.presentationHighlighterFadeEnabled
                ? Colors.amber.withOpacity(isSelected ? 0.25 : 0.1)
                : Colors.grey.withOpacity(isSelected ? 0.2 : 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected
                  ? (widget.presentationHighlighterFadeEnabled
                      ? Colors.amber[700]!
                      : Colors.grey[500]!)
                  : (widget.presentationHighlighterFadeEnabled
                      ? Colors.amber[400]!
                      : Colors.grey[400]!),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Icon(
            Icons.draw_outlined,
            size: 20,
            // ON일 때 노란색, OFF일 때 회색 (선택 여부에 따라 진하기 조절)
            color: widget.presentationHighlighterFadeEnabled
                ? (isSelected ? Colors.amber[800] : Colors.amber[600])
                : (isSelected ? Colors.grey[600] : Colors.grey[500]),
          ),
        ),
      ),
    );
  }

  /// Show presentation highlighter speed panel
  void _showPresentationHighlighterSpeedPanel(BuildContext context) {
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);

    // 패널 닫기 함수
    void closePanel() {
      _currentOverlay?.remove();
      _currentOverlay = null;
    }

    // 기존 패널 닫기
    closePanel();

    // 패널 오픈 콜백 전달 (캔버스 터치 시 패널 닫기 위해)
    widget.onPanelOpened?.call(closePanel);

    _currentOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // 배경 터치 시 패널 닫기
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: closePanel,
              child: Container(color: Colors.transparent),
            ),
          ),
          // 패널
          Positioned(
            left: position.dx - 40,
            top: position.dy + 40, // 툴바 아래로 패널 표시
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '사라지는 속도',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSpeedButton(0.075, '느림', closePanel), // ~33초
                        const SizedBox(width: 8),
                        _buildSpeedButton(1.0, '보통', closePanel), // 2.5초
                        const SizedBox(width: 8),
                        _buildSpeedButton(2.5, '빠름', closePanel), // 1초
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_currentOverlay!);
  }

  /// Build speed selection button
  Widget _buildSpeedButton(double speed, String label, VoidCallback closePanel) {
    final isSelected = (widget.presentationHighlighterFadeSpeed - speed).abs() < 0.1;

    return GestureDetector(
      onTap: () {
        widget.onPresentationHighlighterFadeSpeedChanged?.call(speed);
        closePanel();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber.withOpacity(0.3) : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.amber[700]! : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.amber[800] : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  Widget _buildColorButton(Color color) {
    final isSelected = widget.currentColor.value == color.value;
    // For highlighter, compare with opacity
    final isHighlighterColor = widget.currentTool == DrawingTool.highlighter &&
        widget.currentColor.withOpacity(1.0).value == color.value;
    final selected = isSelected || isHighlighterColor;

    return Tooltip(
      message: _getColorName(color),
      child: InkWell(
        onTap: () => widget.onColorChanged(color),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            border: selected ? Border.all(color: Colors.blue, width: 2) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              border: color == Colors.white || color.computeLuminance() > 0.9
                  ? Border.all(color: Colors.grey[300]!)
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWidthButton(double width) {
    final isSelected = (widget.currentWidth - width).abs() < 0.5;
    return Tooltip(
      message: '${width.toInt()}px',
      child: InkWell(
        onTap: () => widget.onWidthChanged(width),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.withOpacity(0.1) : null,
            borderRadius: BorderRadius.circular(6),
            border: isSelected ? Border.all(color: Colors.blue, width: 1.5) : null,
          ),
          child: Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            child: Container(
              width: width.clamp(2.0, 12.0),
              height: width.clamp(2.0, 12.0),
              decoration: BoxDecoration(
                color: isSelected ? Colors.blue : Colors.grey[700],
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEraserWidthButton(double width) {
    final isSelected = (widget.eraserWidth - width).abs() < 0.5;
    return Tooltip(
      message: '지우개 ${width.toInt()}px',
      child: InkWell(
        onTap: () => widget.onEraserWidthChanged(width),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.orange.withOpacity(0.1) : null,
            borderRadius: BorderRadius.circular(6),
            border: isSelected ? Border.all(color: Colors.orange, width: 1.5) : null,
          ),
          child: Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            child: Container(
              width: (width / 5).clamp(4.0, 16.0),
              height: (width / 5).clamp(4.0, 16.0),
              decoration: BoxDecoration(
                color: isSelected ? Colors.orange : Colors.grey[500],
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey[400]!, width: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 펜 크기 드롭다운 메뉴
  Widget _buildPenWidthDropdown() {
    return Tooltip(
      message: '펜 굵기',
      child: PopupMenuButton<double>(
        tooltip: '',
        onSelected: widget.onWidthChanged,
        offset: const Offset(0, -300),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 현재 펜 크기 표시
              Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                child: Container(
                  width: widget.currentWidth.clamp(2.0, 12.0),
                  height: widget.currentWidth.clamp(2.0, 12.0),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _formatWidth(widget.currentWidth),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
              const Icon(Icons.arrow_drop_up, size: 16, color: Colors.blue),
            ],
          ),
        ),
        itemBuilder: (context) => [
          // 헤더
          PopupMenuItem<double>(
            enabled: false,
            child: Text(
              '펜 굵기',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
          ),
          // 펜 크기 목록
          ...QuickToolbar.penWidthPresets.map((width) {
            final isSelected = (widget.currentWidth - width).abs() < 0.1;
            return PopupMenuItem<double>(
              value: width,
              child: Row(
                children: [
                  // 크기 미리보기 원
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    child: Container(
                      width: width.clamp(2.0, 16.0),
                      height: width.clamp(2.0, 16.0),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.blue : Colors.grey[700],
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _formatWidth(width),
                    style: TextStyle(
                      color: isSelected ? Colors.blue : Colors.grey[800],
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  if (isSelected) ...[
                    const Spacer(),
                    const Icon(Icons.check, size: 18, color: Colors.blue),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 형광펜 설정 드롭다운 (크기 + 투명도)
  Widget _buildHighlighterWidthDropdown() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 크기 드롭다운
        Tooltip(
          message: '형광펜 굵기',
          child: PopupMenuButton<double>(
            tooltip: '',
            onSelected: widget.onWidthChanged,
            offset: const Offset(0, -280),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 현재 형광펜 크기 표시 (사각형)
                  Container(
                    width: 16,
                    height: 12,
                    decoration: BoxDecoration(
                      color: widget.currentColor.withOpacity(widget.highlighterOpacity),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatWidth(widget.currentWidth),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber[800],
                    ),
                  ),
                  Icon(Icons.arrow_drop_up, size: 16, color: Colors.amber[700]),
                ],
              ),
            ),
            itemBuilder: (context) => [
              // 헤더
              PopupMenuItem<double>(
                enabled: false,
                child: Text(
                  '형광펜 굵기',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                ),
              ),
              // 형광펜 크기 목록
              ...QuickToolbar.highlighterWidthPresets.map((width) {
                final isSelected = (widget.currentWidth - width).abs() < 0.1;
                return PopupMenuItem<double>(
                  value: width,
                  child: Row(
                    children: [
                      // 크기 미리보기 (형광펜은 사각형으로 표시)
                      Container(
                        width: 24,
                        height: (width / 3).clamp(6.0, 16.0),
                        decoration: BoxDecoration(
                          color: widget.currentColor.withOpacity(widget.highlighterOpacity),
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: isSelected ? Colors.amber[700]! : Colors.grey[300]!,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _formatWidth(width),
                        style: TextStyle(
                          color: isSelected ? Colors.amber[800] : Colors.grey[800],
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      if (isSelected) ...[
                        const Spacer(),
                        Icon(Icons.check, size: 18, color: Colors.amber[700]),
                      ],
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(width: 4),
        // 투명도 드롭다운
        _buildHighlighterOpacityDropdown(),
      ],
    );
  }

  /// 형광펜 투명도 드롭다운
  Widget _buildHighlighterOpacityDropdown() {
    return Tooltip(
      message: '형광펜 투명도',
      child: PopupMenuButton<double>(
        tooltip: '',
        onSelected: widget.onHighlighterOpacityChanged,
        offset: const Offset(0, -280),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.amber.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.opacity, size: 16, color: Colors.amber[700]),
              const SizedBox(width: 2),
              Text(
                '${(widget.highlighterOpacity * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber[800],
                ),
              ),
              Icon(Icons.arrow_drop_up, size: 14, color: Colors.amber[700]),
            ],
          ),
        ),
        itemBuilder: (context) => [
          // 헤더
          PopupMenuItem<double>(
            enabled: false,
            child: Text(
              '투명도',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
          ),
          // 투명도 목록
          ...QuickToolbar.highlighterOpacityPresets.map((opacity) {
            final isSelected = (widget.highlighterOpacity - opacity).abs() < 0.05;
            return PopupMenuItem<double>(
              value: opacity,
              child: Row(
                children: [
                  // 투명도 미리보기
                  Container(
                    width: 24,
                    height: 12,
                    decoration: BoxDecoration(
                      color: widget.currentColor.withOpacity(opacity),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: isSelected ? Colors.amber[700]! : Colors.grey[300]!,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${(opacity * 100).toInt()}%',
                    style: TextStyle(
                      color: isSelected ? Colors.amber[800] : Colors.grey[800],
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  if (isSelected) ...[
                    const Spacer(),
                    Icon(Icons.check, size: 18, color: Colors.amber[700]),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 펜 굵기 표시 포맷
  String _formatWidth(double width) {
    if (width == width.toInt().toDouble()) {
      return '${width.toInt()}pt';
    } else {
      return '${width}pt';
    }
  }

  String _getColorName(Color color) {
    if (color == Colors.black) return '검정';
    if (color.value == const Color(0xFF1976D2).value) return '파랑';
    if (color.value == const Color(0xFFD32F2F).value) return '빨강';
    if (color.value == const Color(0xFF388E3C).value) return '초록';
    if (color.value == const Color(0xFFF57C00).value) return '주황';
    if (color.value == const Color(0xFF7B1FA2).value) return '보라';
    if (color.value == const Color(0xFFFFEB3B).value) return '노랑';
    return '색상';
  }
}

/// 펜 설정 패널 Overlay (캔버스 터치 허용)
class _PenPanelOverlay extends StatefulWidget {
  final Offset buttonPosition;
  final Color currentColor;
  final double currentWidth;
  final void Function(Color) onColorChanged;
  final void Function(double) onWidthChanged;
  final VoidCallback onClose;
  final List<Color> defaultColors;

  const _PenPanelOverlay({
    required this.buttonPosition,
    required this.currentColor,
    required this.currentWidth,
    required this.onColorChanged,
    required this.onWidthChanged,
    required this.onClose,
    required this.defaultColors,
  });

  @override
  State<_PenPanelOverlay> createState() => _PenPanelOverlayState();
}

class _PenPanelOverlayState extends State<_PenPanelOverlay> {
  late Color _localColor;
  late double _localWidth;

  @override
  void initState() {
    super.initState();
    _localColor = widget.currentColor;
    _localWidth = widget.currentWidth;
  }

  String _formatWidth(double width) {
    if (width == width.toInt().toDouble()) {
      return '${width.toInt()}pt';
    } else {
      return '${width}pt';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.buttonPosition.dx - 50,
      top: widget.buttonPosition.dy + 40, // 툴바 아래로 패널 표시
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 색상 섹션 (2줄 레이아웃)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '색상',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 6),
                  // 1열 (5개)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.defaultColors.take(5).map((color) {
                      final isThisColorSelected = _localColor.value == color.value;
                      return Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerUp: (_) {
                          setState(() => _localColor = color);
                          widget.onColorChanged(color);
                        },
                        child: Container(
                          width: 26,
                          height: 26,
                          margin: const EdgeInsets.all(1.5),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isThisColorSelected ? Colors.blue : Colors.grey[300]!,
                              width: isThisColorSelected ? 2.5 : 1,
                            ),
                          ),
                          child: isThisColorSelected
                              ? Icon(Icons.check, size: 14, color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  // 2열 (5개)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.defaultColors.skip(5).map((color) {
                      final isThisColorSelected = _localColor.value == color.value;
                      return Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerUp: (_) {
                          setState(() => _localColor = color);
                          widget.onColorChanged(color);
                        },
                        child: Container(
                          width: 26,
                          height: 26,
                          margin: const EdgeInsets.all(1.5),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isThisColorSelected ? Colors.blue : Colors.grey[300]!,
                              width: isThisColorSelected ? 2.5 : 1,
                            ),
                          ),
                          child: isThisColorSelected
                              ? Icon(Icons.check, size: 14, color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              // 구분선
              Container(
                width: 1,
                height: 70,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: Colors.grey[300],
              ),
              // 굵기 섹션
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '굵기',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: QuickToolbar.penWidthPresets.take(5).map((width) {
                      final isThisWidthSelected = (_localWidth - width).abs() < 0.1;
                      return Tooltip(
                        message: _formatWidth(width),
                        child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerUp: (_) {
                            setState(() => _localWidth = width);
                            widget.onWidthChanged(width);
                          },
                          child: Container(
                            width: 28,
                            height: 28,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: isThisWidthSelected ? Colors.blue[700]!.withOpacity(0.1) : null,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isThisWidthSelected ? Colors.blue[700]! : Colors.grey[300]!,
                                width: isThisWidthSelected ? 2 : 1,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                width == width.toInt().toDouble() ? '${width.toInt()}' : '$width',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: isThisWidthSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isThisWidthSelected ? Colors.blue[700] : Colors.grey[800],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 형광펜 패널 오버레이 (Overlay 방식 - 캔버스 터치 허용)
class _HighlighterPanelOverlay extends StatefulWidget {
  final Offset buttonPosition;
  final Color currentColor;
  final double currentWidth;
  final double currentOpacity;
  final void Function(Color) onColorChanged;
  final void Function(double) onWidthChanged;
  final void Function(double) onOpacityChanged;
  final VoidCallback onClose;

  const _HighlighterPanelOverlay({
    required this.buttonPosition,
    required this.currentColor,
    required this.currentWidth,
    required this.currentOpacity,
    required this.onColorChanged,
    required this.onWidthChanged,
    required this.onOpacityChanged,
    required this.onClose,
  });

  @override
  State<_HighlighterPanelOverlay> createState() => _HighlighterPanelOverlayState();
}

class _HighlighterPanelOverlayState extends State<_HighlighterPanelOverlay> {
  late Color _localColor;
  late double _localWidth;
  late double _localOpacity;

  @override
  void initState() {
    super.initState();
    _localColor = widget.currentColor;
    _localWidth = widget.currentWidth;
    _localOpacity = widget.currentOpacity;
  }

  String _formatWidth(double width) {
    if (width == width.toInt().toDouble()) {
      return '${width.toInt()}pt';
    } else {
      return '${width}pt';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.buttonPosition.dx - 100,
      top: widget.buttonPosition.dy + 40, // 툴바 아래로 패널 표시
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 색상 섹션 (2줄 레이아웃)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '색상',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 6),
                  // 1열 (5개)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: QuickToolbar.highlighterColors.take(5).map((color) {
                      final isThisColorSelected = _localColor.value == color.value;
                      return Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerUp: (_) {
                          setState(() => _localColor = color);
                          widget.onColorChanged(color);
                        },
                        child: Container(
                          width: 26,
                          height: 26,
                          margin: const EdgeInsets.all(1.5),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isThisColorSelected ? Colors.amber[700]! : Colors.grey[300]!,
                              width: isThisColorSelected ? 2.5 : 1,
                            ),
                          ),
                          child: isThisColorSelected
                              ? Icon(Icons.check, size: 14, color: Colors.amber[900])
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  // 2열 (5개)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: QuickToolbar.highlighterColors.skip(5).map((color) {
                      final isThisColorSelected = _localColor.value == color.value;
                      return Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerUp: (_) {
                          setState(() => _localColor = color);
                          widget.onColorChanged(color);
                        },
                        child: Container(
                          width: 26,
                          height: 26,
                          margin: const EdgeInsets.all(1.5),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isThisColorSelected ? Colors.amber[700]! : Colors.grey[300]!,
                              width: isThisColorSelected ? 2.5 : 1,
                            ),
                          ),
                          child: isThisColorSelected
                              ? Icon(Icons.check, size: 14, color: Colors.amber[900])
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              // 구분선
              Container(
                width: 1,
                height: 70,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: Colors.grey[300],
              ),
              // 굵기 섹션
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '굵기',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: QuickToolbar.highlighterWidthPresets.take(5).map((width) {
                      final isThisWidthSelected = (_localWidth - width).abs() < 0.1;
                      return Tooltip(
                        message: _formatWidth(width),
                        child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerUp: (_) {
                            setState(() => _localWidth = width);
                            widget.onWidthChanged(width);
                          },
                          child: Container(
                            width: 28,
                            height: 28,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: isThisWidthSelected ? Colors.amber.withOpacity(0.2) : null,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isThisWidthSelected ? Colors.amber[700]! : Colors.grey[300]!,
                                width: isThisWidthSelected ? 2 : 1,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '${width.toInt()}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: isThisWidthSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isThisWidthSelected ? Colors.amber[800] : Colors.grey[800],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              // 구분선
              Container(
                width: 1,
                height: 70,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: Colors.grey[300],
              ),
              // 투명도 섹션
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '투명도',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: QuickToolbar.highlighterOpacityPresets.take(5).map((opacity) {
                      final isThisOpacitySelected = (_localOpacity - opacity).abs() < 0.05;
                      return Tooltip(
                        message: '${(opacity * 100).toInt()}%',
                        child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerUp: (_) {
                            setState(() => _localOpacity = opacity);
                            widget.onOpacityChanged(opacity);
                          },
                          child: Container(
                            width: 28,
                            height: 28,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: isThisOpacitySelected ? Colors.amber.withOpacity(0.2) : null,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isThisOpacitySelected ? Colors.amber[700]! : Colors.grey[300]!,
                                width: isThisOpacitySelected ? 2 : 1,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '${(opacity * 100).toInt()}',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: isThisOpacitySelected ? FontWeight.bold : FontWeight.normal,
                                  color: isThisOpacitySelected ? Colors.amber[800] : Colors.grey[800],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 지우개 패널 오버레이 (Overlay 방식 - 캔버스 터치 허용)
class _EraserPanelOverlay extends StatefulWidget {
  final Offset buttonPosition;
  final double currentWidth;
  final void Function(double) onWidthChanged;
  final VoidCallback onClose;
  final DrawingTool currentTool;
  final void Function(DrawingTool) onToolChanged;

  const _EraserPanelOverlay({
    required this.buttonPosition,
    required this.currentWidth,
    required this.onWidthChanged,
    required this.onClose,
    required this.currentTool,
    required this.onToolChanged,
  });

  @override
  State<_EraserPanelOverlay> createState() => _EraserPanelOverlayState();
}

class _EraserPanelOverlayState extends State<_EraserPanelOverlay> {
  late double _localWidth;
  late DrawingTool _localTool;

  @override
  void initState() {
    super.initState();
    _localWidth = widget.currentWidth;
    _localTool = widget.currentTool;
  }

  @override
  Widget build(BuildContext context) {
    final isEraserSelected = _localTool == DrawingTool.eraser;
    final isAreaEraserSelected = _localTool == DrawingTool.areaEraser;

    return Positioned(
      left: widget.buttonPosition.dx - 40,
      top: widget.buttonPosition.dy + 40, // 툴바 아래로 패널 표시
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 지우개 모드 선택
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 일반 지우개
                  Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerUp: (_) {
                      setState(() => _localTool = DrawingTool.eraser);
                      widget.onToolChanged(DrawingTool.eraser);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isEraserSelected ? Colors.orange.withOpacity(0.2) : null,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isEraserSelected ? Colors.orange : Colors.grey[300]!,
                          width: isEraserSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_fix_normal,
                            size: 14,
                            color: isEraserSelected ? Colors.orange : Colors.grey[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '획 지우개',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isEraserSelected ? FontWeight.bold : FontWeight.normal,
                              color: isEraserSelected ? Colors.orange : Colors.grey[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 영역 지우개
                  Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerUp: (_) {
                      setState(() => _localTool = DrawingTool.areaEraser);
                      widget.onToolChanged(DrawingTool.areaEraser);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isAreaEraserSelected ? Colors.red.withOpacity(0.2) : null,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isAreaEraserSelected ? Colors.red : Colors.grey[300]!,
                          width: isAreaEraserSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.select_all,
                            size: 14,
                            color: isAreaEraserSelected ? Colors.red : Colors.grey[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '영역 지우개',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isAreaEraserSelected ? FontWeight.bold : FontWeight.normal,
                              color: isAreaEraserSelected ? Colors.red : Colors.grey[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // 지우개 크기 (일반 지우개 선택 시에만 표시)
              if (isEraserSelected) ...[
                const SizedBox(height: 10),
                Text(
                  '지우개 크기',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: QuickToolbar.eraserWidths.map((width) {
                    final isThisWidthSelected = (_localWidth - width).abs() < 0.5;
                    return Tooltip(
                      message: '${width.toInt()}px',
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerUp: (_) {
                          setState(() => _localWidth = width);
                          widget.onWidthChanged(width);
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: isThisWidthSelected ? Colors.orange.withOpacity(0.2) : null,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isThisWidthSelected ? Colors.orange : Colors.grey[300]!,
                              width: isThisWidthSelected ? 2 : 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${width.toInt()}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: isThisWidthSelected ? FontWeight.bold : FontWeight.normal,
                                color: isThisWidthSelected ? Colors.orange : Colors.grey[800],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
