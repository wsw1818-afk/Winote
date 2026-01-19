import 'package:flutter/material.dart';
import '../../../core/providers/drawing_state.dart';
import '../../../core/services/settings_service.dart';

/// Quick toolbar for tool selection and fast access
/// (실행취소/다시실행/색상/굵기 슬라이더는 DrawingToolbar에서 담당)
class QuickToolbar extends StatefulWidget {
  final DrawingTool currentTool;
  final Color currentColor;
  final double currentWidth;
  final double eraserWidth;
  final double highlighterOpacity; // 형광펜 투명도 (0.0 ~ 1.0)
  final PageTemplate currentTemplate;
  final void Function(DrawingTool) onToolChanged;
  final void Function(Color) onColorChanged;
  final void Function(double) onWidthChanged;
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
  // Laser pointer color
  final Color laserPointerColor;
  final void Function(Color)? onLaserPointerColorChanged;
  // Presentation highlighter fade mode
  final bool presentationHighlighterFadeEnabled;
  final void Function(bool)? onPresentationHighlighterFadeChanged;

  const QuickToolbar({
    super.key,
    required this.currentTool,
    required this.currentColor,
    required this.currentWidth,
    this.eraserWidth = 20.0,
    this.highlighterOpacity = 0.4,
    required this.currentTemplate,
    required this.onToolChanged,
    required this.onColorChanged,
    required this.onWidthChanged,
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
    this.laserPointerColor = Colors.red,
    this.onLaserPointerColorChanged,
    this.presentationHighlighterFadeEnabled = true,
    this.onPresentationHighlighterFadeChanged,
  });

  // Preset widths for pen (다양한 크기 프리셋)
  static const List<double> penWidthPresets = [0.5, 1.0, 2.0, 3.0, 5.0, 8.0, 12.0, 20.0];
  // Preset widths for eraser
  static const List<double> eraserWidths = [10.0, 20.0, 40.0, 60.0];
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

  // 기본 프리셋 색상 (초기값, 설정 로드 전) - 14개 확장
  static const List<Color> _defaultColors = [
    // 1열 (7개)
    Colors.black,
    Color(0xFF424242), // Dark Gray
    Color(0xFF1976D2), // Blue
    Color(0xFF0097A7), // Cyan
    Color(0xFF388E3C), // Green
    Color(0xFF689F38), // Light Green
    Color(0xFFFFEB3B), // Yellow
    // 2열 (7개)
    Colors.white,
    Color(0xFF795548), // Brown
    Color(0xFFD32F2F), // Red
    Color(0xFFE91E63), // Pink
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
          // Drawing tools with dropdown menus
          _buildPenToolButton(context), // 펜 (색상 + 굵기)
          _buildHighlighterToolButton(context), // 형광펜 (색상 + 굵기 + 투명도)
          _buildEraserToolButton(context), // 지우개 (굵기)
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
        ],
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
    return Tooltip(
      message: '페이지 템플릿',
      child: PopupMenuButton<PageTemplate>(
        tooltip: '', // 기본 "Show menu" 툴팁 비활성화
        onSelected: widget.onTemplateChanged,
        offset: const Offset(0, -200),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_getTemplateIcon(widget.currentTemplate), size: 20, color: Colors.blue),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_up, size: 16, color: Colors.blue),
            ],
          ),
        ),
        itemBuilder: (context) => [
          _buildTemplateMenuItem(PageTemplate.blank, Icons.crop_square, '빈 페이지'),
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

  /// 펜 설정 패널 표시
  void _showPenPanel(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);

    // 패널 내에서 선택했는지 추적하는 플래그
    bool colorSelectedInPanel = false;
    bool widthSelectedInPanel = false;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Stack(
          children: [
            // 배경 터치시 닫기 (선택이 완료된 경우에만)
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  // 패널 내에서 색상과 굵기 모두 선택했으면 닫기
                  if (colorSelectedInPanel && widthSelectedInPanel) {
                    Navigator.pop(context);
                  }
                },
                child: Container(color: Colors.transparent),
              ),
            ),
            // 패널
            Positioned(
              left: buttonPosition.dx - 50,
              top: buttonPosition.dy - 90,
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
                          // 1열 (7개)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: _defaultColors.take(7).map((color) {
                              final isThisColorSelected = widget.currentColor.value == color.value;
                              return GestureDetector(
                                onTap: () {
                                  widget.onColorChanged(color);
                                  colorSelectedInPanel = true;
                                  setDialogState(() {}); // 다이얼로그 상태 업데이트
                                  // 모두 선택되면 닫기
                                  if (widthSelectedInPanel) {
                                    Navigator.pop(context);
                                  }
                                },
                                child: Container(
                                  width: 26,
                                  height: 26,
                                  margin: const EdgeInsets.all(1.5),
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isThisColorSelected ? Colors.blue : (color == Colors.white ? Colors.grey[400]! : Colors.grey[300]!),
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
                          // 2열 (7개)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: _defaultColors.skip(7).map((color) {
                              final isThisColorSelected = widget.currentColor.value == color.value;
                              return GestureDetector(
                                onTap: () {
                                  widget.onColorChanged(color);
                                  colorSelectedInPanel = true;
                                  setDialogState(() {}); // 다이얼로그 상태 업데이트
                                  // 모두 선택되면 닫기
                                  if (widthSelectedInPanel) {
                                    Navigator.pop(context);
                                  }
                                },
                                child: Container(
                                  width: 26,
                                  height: 26,
                                  margin: const EdgeInsets.all(1.5),
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isThisColorSelected ? Colors.blue : (color == Colors.white ? Colors.grey[400]! : Colors.grey[300]!),
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
                            children: QuickToolbar.penWidthPresets.take(6).map((width) {
                              final isThisWidthSelected = (widget.currentWidth - width).abs() < 0.1;
                              return Tooltip(
                                message: _formatWidth(width),
                                child: GestureDetector(
                                  onTap: () {
                                    widget.onWidthChanged(width);
                                    widthSelectedInPanel = true;
                                    setDialogState(() {}); // 다이얼로그 상태 업데이트
                                    // 모두 선택되면 닫기
                                    if (colorSelectedInPanel) {
                                      Navigator.pop(context);
                                    }
                                  },
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    margin: const EdgeInsets.symmetric(horizontal: 2),
                                    decoration: BoxDecoration(
                                      color: isThisWidthSelected ? Colors.blue.withOpacity(0.1) : null,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isThisWidthSelected ? Colors.blue : Colors.grey[300]!,
                                        width: isThisWidthSelected ? 2 : 1,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        width == width.toInt().toDouble() ? '${width.toInt()}' : '$width',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: isThisWidthSelected ? FontWeight.bold : FontWeight.normal,
                                          color: isThisWidthSelected ? Colors.blue : Colors.grey[800],
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
            ),
          ],
        ),
      ),
    );
  }

  /// 형광펜 도구 버튼 (색상 + 굵기 + 투명도 가로 패널)
  Widget _buildHighlighterToolButton(BuildContext context) {
    final isSelected = widget.currentTool == DrawingTool.highlighter;
    final currentHighlighterColor = widget.currentColor.withOpacity(1.0);

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

  /// 형광펜 설정 패널 표시
  void _showHighlighterPanel(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);

    // 패널 내에서 선택했는지 추적하는 플래그
    bool colorSelectedInPanel = false;
    bool widthSelectedInPanel = false;
    bool opacitySelectedInPanel = false;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final currentHighlighterColor = widget.currentColor.withOpacity(1.0);
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    // 패널 내에서 모든 항목을 선택했으면 닫기
                    if (colorSelectedInPanel && widthSelectedInPanel && opacitySelectedInPanel) {
                      Navigator.pop(context);
                    }
                  },
                  child: Container(color: Colors.transparent),
                ),
              ),
              Positioned(
                left: buttonPosition.dx - 100,
                top: buttonPosition.dy - 110,
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
                                final isThisColorSelected = currentHighlighterColor.value == color.value;
                                return GestureDetector(
                                  onTap: () {
                                    widget.onColorChanged(color);
                                    colorSelectedInPanel = true;
                                    setDialogState(() {}); // 다이얼로그 상태 업데이트
                                    // 모두 선택되면 닫기
                                    if (widthSelectedInPanel && opacitySelectedInPanel) {
                                      Navigator.pop(context);
                                    }
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
                                final isThisColorSelected = currentHighlighterColor.value == color.value;
                                return GestureDetector(
                                  onTap: () {
                                    widget.onColorChanged(color);
                                    colorSelectedInPanel = true;
                                    setDialogState(() {}); // 다이얼로그 상태 업데이트
                                    // 모두 선택되면 닫기
                                    if (widthSelectedInPanel && opacitySelectedInPanel) {
                                      Navigator.pop(context);
                                    }
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
                                final isThisWidthSelected = (widget.currentWidth - width).abs() < 0.1;
                                return Tooltip(
                                  message: _formatWidth(width),
                                  child: GestureDetector(
                                    onTap: () {
                                      widget.onWidthChanged(width);
                                      widthSelectedInPanel = true;
                                      setDialogState(() {}); // 다이얼로그 상태 업데이트
                                      // 모두 선택되면 닫기
                                      if (colorSelectedInPanel && opacitySelectedInPanel) {
                                        Navigator.pop(context);
                                      }
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
                                            // 선택 안됐을 때도 글자가 잘 보이도록 더 진한 색상 사용
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
                                final isThisOpacitySelected = (widget.highlighterOpacity - opacity).abs() < 0.05;
                                return Tooltip(
                                  message: '${(opacity * 100).toInt()}%',
                                  child: GestureDetector(
                                    onTap: () {
                                      widget.onHighlighterOpacityChanged(opacity);
                                      opacitySelectedInPanel = true;
                                      setDialogState(() {}); // 다이얼로그 상태 업데이트
                                      // 모두 선택되면 닫기
                                      if (colorSelectedInPanel && widthSelectedInPanel) {
                                        Navigator.pop(context);
                                      }
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
              ),
            ],
          );
        },
      ),
    );
  }

  /// 지우개 도구 버튼 (굵기 가로 패널)
  Widget _buildEraserToolButton(BuildContext context) {
    final isSelected = widget.currentTool == DrawingTool.eraser;

    return Tooltip(
      message: '지우개',
      child: GestureDetector(
        onTap: () {
          widget.onToolChanged(DrawingTool.eraser);
          _showEraserPanel(context);
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
                    Icons.auto_fix_normal,
                    size: 20,
                    color: isSelected ? Colors.blue : Colors.grey[700],
                  ),
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
                color: isSelected ? Colors.blue : Colors.grey[700],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 지우개 설정 패널 표시
  void _showEraserPanel(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);

    // 패널 내에서 선택했는지 추적하는 플래그
    bool widthSelectedInPanel = false;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  // 패널 내에서 크기를 선택했으면 닫기
                  if (widthSelectedInPanel) {
                    Navigator.pop(context);
                  }
                },
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: buttonPosition.dx - 40,
              top: buttonPosition.dy - 90,
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
                        '지우개 크기',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: QuickToolbar.eraserWidths.map((width) {
                          final isThisWidthSelected = (widget.eraserWidth - width).abs() < 0.5;
                          return Tooltip(
                            message: '${width.toInt()}px',
                            child: GestureDetector(
                              onTap: () {
                                widget.onEraserWidthChanged(width);
                                widthSelectedInPanel = true;
                                setDialogState(() {}); // 다이얼로그 상태 업데이트
                                // 선택되면 닫기 (지우개는 굵기만 선택하면 됨)
                                Navigator.pop(context);
                              },
                              child: Container(
                                width: 32,
                                height: 32,
                                margin: const EdgeInsets.symmetric(horizontal: 4),
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
                                      fontSize: 11,
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
                  ),
                ),
              ),
            ),
          ],
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
                  top: buttonPosition.dy - 120, // 버튼 위쪽으로 팝업 표시
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

  /// Build presentation highlighter tool button - tap toggles fade ON/OFF
  Widget _buildPresentationHighlighterToolButton(BuildContext context) {
    final isSelected = widget.currentTool == DrawingTool.presentationHighlighter;

    return Tooltip(
      message: widget.presentationHighlighterFadeEnabled
          ? '프레젠테이션 형광펜 ON (탭하여 OFF)'
          : '프레젠테이션 형광펜 OFF (탭하여 ON)',
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
