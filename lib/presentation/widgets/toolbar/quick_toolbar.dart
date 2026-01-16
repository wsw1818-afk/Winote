import 'package:flutter/material.dart';
import '../../../core/providers/drawing_state.dart';
import '../../../core/services/settings_service.dart';

/// Quick toolbar for tool selection and fast access
/// (실행취소/다시실행/색상/굵기 슬라이더는 DrawingToolbar에서 담당)
class QuickToolbar extends StatefulWidget {
  final DrawingTool currentTool;
  final Color currentColor;
  final double currentWidth;
  final PageTemplate currentTemplate;
  final void Function(DrawingTool) onToolChanged;
  final void Function(Color) onColorChanged;
  final void Function(double) onWidthChanged;
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

  const QuickToolbar({
    super.key,
    required this.currentTool,
    required this.currentColor,
    required this.currentWidth,
    required this.currentTemplate,
    required this.onToolChanged,
    required this.onColorChanged,
    required this.onWidthChanged,
    required this.onTemplateChanged,
    this.hasSelection = false,
    this.onCopySelection,
    this.onDeleteSelection,
    this.onClearSelection,
    this.onInsertImage,
    this.onInsertText,
    this.onInsertTable,
  });

  // Preset widths
  static const List<double> presetWidths = [1.0, 2.0, 4.0, 8.0];

  @override
  State<QuickToolbar> createState() => _QuickToolbarState();
}

class _QuickToolbarState extends State<QuickToolbar> {
  final SettingsService _settings = SettingsService.instance;
  List<Color> _favoriteColors = [];

  // 기본 프리셋 색상 (초기값, 설정 로드 전)
  static const List<Color> _defaultColors = [
    Colors.black,
    Color(0xFF1976D2), // Blue
    Color(0xFFD32F2F), // Red
    Color(0xFF388E3C), // Green
    Color(0xFFF57C00), // Orange
    Color(0xFF7B1FA2), // Purple
    Color(0xFFFFEB3B), // Yellow (highlighter)
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
          // Drawing tools
          _buildToolButton(DrawingTool.pen, Icons.edit, '펜'),
          _buildToolButton(DrawingTool.highlighter, Icons.brush, '형광펜'),
          _buildToolButton(DrawingTool.eraser, Icons.auto_fix_normal, '지우개'),
          _buildToolButton(DrawingTool.lasso, Icons.gesture, '올가미'),
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

          // Quick favorite colors (from settings)
          ..._favoriteColors.take(8).map((color) => _buildColorButton(color)),
          // 색상 추가/관리 버튼
          _buildColorManagerButton(context),
          _buildDivider(),

          // Quick widths
          ...QuickToolbar.presetWidths.map((width) => _buildWidthButton(width)),
          _buildDivider(),

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

  Widget _buildShapeToolButton(BuildContext context) {
    final isSelected = _isShapeTool;
    final currentShapeIcon = isSelected ? _getShapeIcon(widget.currentTool) : Icons.category;

    return Tooltip(
      message: '도형',
      child: PopupMenuButton<DrawingTool>(
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
