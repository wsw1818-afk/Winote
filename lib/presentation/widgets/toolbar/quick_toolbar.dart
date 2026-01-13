import 'package:flutter/material.dart';
import '../../../core/providers/drawing_state.dart';

/// Quick toolbar for fast pen/color/width switching
class QuickToolbar extends StatelessWidget {
  final DrawingTool currentTool;
  final Color currentColor;
  final double currentWidth;
  final PageTemplate currentTemplate;
  final void Function(DrawingTool) onToolChanged;
  final void Function(Color) onColorChanged;
  final void Function(double) onWidthChanged;
  final void Function(PageTemplate) onTemplateChanged;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final bool canUndo;
  final bool canRedo;
  // Lasso selection callbacks
  final bool hasSelection;
  final VoidCallback? onCopySelection;
  final VoidCallback? onDeleteSelection;
  final VoidCallback? onClearSelection;

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
    this.onUndo,
    this.onRedo,
    this.canUndo = false,
    this.canRedo = false,
    this.hasSelection = false,
    this.onCopySelection,
    this.onDeleteSelection,
    this.onClearSelection,
  });

  // Preset colors for quick access
  static const List<Color> presetColors = [
    Colors.black,
    Color(0xFF1976D2), // Blue
    Color(0xFFD32F2F), // Red
    Color(0xFF388E3C), // Green
    Color(0xFFF57C00), // Orange
    Color(0xFF7B1FA2), // Purple
    Color(0xFFFFEB3B), // Yellow (highlighter)
  ];

  // Preset widths
  static const List<double> presetWidths = [1.0, 2.0, 4.0, 8.0];

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
          // Undo/Redo
          _buildIconButton(
            Icons.undo,
            onUndo,
            enabled: canUndo,
            tooltip: '실행취소',
          ),
          _buildIconButton(
            Icons.redo,
            onRedo,
            enabled: canRedo,
            tooltip: '다시실행',
          ),
          _buildDivider(),

          // Drawing tools
          _buildToolButton(DrawingTool.pen, Icons.edit, '펜'),
          _buildToolButton(DrawingTool.highlighter, Icons.brush, '형광펜'),
          _buildToolButton(DrawingTool.eraser, Icons.auto_fix_normal, '지우개'),
          _buildToolButton(DrawingTool.lasso, Icons.gesture, '올가미'),
          _buildDivider(),

          // Selection actions (only show when has selection)
          if (hasSelection) ...[
            _buildIconButton(
              Icons.copy,
              onCopySelection,
              tooltip: '복사',
            ),
            _buildIconButton(
              Icons.delete_outline,
              onDeleteSelection,
              tooltip: '삭제',
            ),
            _buildIconButton(
              Icons.close,
              onClearSelection,
              tooltip: '선택 해제',
            ),
            _buildDivider(),
          ],

          // Quick colors
          ...presetColors.map((color) => _buildColorButton(color)),
          _buildDivider(),

          // Quick widths
          ...presetWidths.map((width) => _buildWidthButton(width)),
          _buildDivider(),

          // Template selector
          _buildTemplateButton(context),
        ],
      ),
    );
  }

  Widget _buildTemplateButton(BuildContext context) {
    return Tooltip(
      message: '페이지 템플릿',
      child: PopupMenuButton<PageTemplate>(
        onSelected: onTemplateChanged,
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
              Icon(_getTemplateIcon(currentTemplate), size: 20, color: Colors.blue),
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

  PopupMenuItem<PageTemplate> _buildTemplateMenuItem(
    PageTemplate template,
    IconData icon,
    String label,
  ) {
    final isSelected = currentTemplate == template;
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
    final isSelected = currentTool == tool;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => onToolChanged(tool),
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
    final isSelected = currentColor.value == color.value;
    // For highlighter, compare with opacity
    final isHighlighterColor = currentTool == DrawingTool.highlighter &&
        currentColor.withOpacity(1.0).value == color.value;
    final selected = isSelected || isHighlighterColor;

    return Tooltip(
      message: _getColorName(color),
      child: InkWell(
        onTap: () => onColorChanged(color),
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
    final isSelected = (currentWidth - width).abs() < 0.5;
    return Tooltip(
      message: '${width.toInt()}px',
      child: InkWell(
        onTap: () => onWidthChanged(width),
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
