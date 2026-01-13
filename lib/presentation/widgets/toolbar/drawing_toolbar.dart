import 'package:flutter/material.dart';
import '../../../core/providers/drawing_state.dart';

/// Drawing toolbar widget with tool selection, color picker, and stroke width
class DrawingToolbar extends StatelessWidget {
  final DrawingTool currentTool;
  final Color currentColor;
  final double currentWidth;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onClear;
  final ValueChanged<DrawingTool> onToolChanged;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onWidthChanged;

  const DrawingToolbar({
    super.key,
    required this.currentTool,
    required this.currentColor,
    required this.currentWidth,
    this.canUndo = false,
    this.canRedo = false,
    this.onUndo,
    this.onRedo,
    this.onClear,
    required this.onToolChanged,
    required this.onColorChanged,
    required this.onWidthChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Undo/Redo buttons
            _buildIconButton(
              icon: Icons.undo,
              onPressed: canUndo ? onUndo : null,
              tooltip: 'Undo',
            ),
            _buildIconButton(
              icon: Icons.redo,
              onPressed: canRedo ? onRedo : null,
              tooltip: 'Redo',
            ),
            const SizedBox(width: 8),
            Container(width: 1, height: 24, color: Colors.grey[300]),
            const SizedBox(width: 8),

            // Tool selection
            _buildToolButton(DrawingTool.pen, Icons.edit),
            _buildToolButton(DrawingTool.highlighter, Icons.highlight),
            _buildToolButton(DrawingTool.eraser, Icons.auto_fix_normal),
            const SizedBox(width: 8),
            Container(width: 1, height: 24, color: Colors.grey[300]),
            const SizedBox(width: 8),

            // Color picker
            _buildColorButton(context),
            const SizedBox(width: 8),

            // Width slider
            Expanded(
              child: _buildWidthSlider(),
            ),
            const SizedBox(width: 8),

            // Clear button
            _buildIconButton(
              icon: Icons.delete_outline,
              onPressed: onClear,
              tooltip: 'Clear All',
              color: Colors.red[400],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    VoidCallback? onPressed,
    String? tooltip,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: IconButton(
        icon: Icon(icon, size: 22),
        color: onPressed != null ? (color ?? Colors.grey[700]) : Colors.grey[400],
        onPressed: onPressed,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    );
  }

  Widget _buildToolButton(DrawingTool tool, IconData icon) {
    final isSelected = currentTool == tool;
    return Tooltip(
      message: tool.name[0].toUpperCase() + tool.name.substring(1),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[100] : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: IconButton(
          icon: Icon(icon, size: 22),
          color: isSelected ? Colors.blue[700] : Colors.grey[700],
          onPressed: () => onToolChanged(tool),
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
      ),
    );
  }

  Widget _buildColorButton(BuildContext context) {
    return Tooltip(
      message: 'Color',
      child: GestureDetector(
        onTap: () => _showColorPicker(context),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: currentColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.grey[400]!,
              width: 2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWidthSlider() {
    return Row(
      children: [
        Icon(Icons.line_weight, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: Colors.blue[400],
              inactiveTrackColor: Colors.grey[300],
              thumbColor: Colors.blue[600],
            ),
            child: Slider(
              value: currentWidth,
              min: 0.5,
              max: 30.0,
              onChanged: onWidthChanged,
            ),
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            currentWidth.toStringAsFixed(1),
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ),
      ],
    );
  }

  void _showColorPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => ColorPickerSheet(
        currentColor: currentColor,
        onColorSelected: (color) {
          onColorChanged(color);
          Navigator.pop(context);
        },
      ),
    );
  }
}

/// Color picker bottom sheet
class ColorPickerSheet extends StatelessWidget {
  final Color currentColor;
  final ValueChanged<Color> onColorSelected;

  const ColorPickerSheet({
    super.key,
    required this.currentColor,
    required this.onColorSelected,
  });

  static const List<Color> colors = [
    Colors.black,
    Color(0xFF424242),
    Color(0xFF757575),
    Color(0xFFBDBDBD),
    Colors.white,
    Color(0xFFF44336), // Red
    Color(0xFFE91E63), // Pink
    Color(0xFF9C27B0), // Purple
    Color(0xFF673AB7), // Deep Purple
    Color(0xFF3F51B5), // Indigo
    Color(0xFF2196F3), // Blue
    Color(0xFF03A9F4), // Light Blue
    Color(0xFF00BCD4), // Cyan
    Color(0xFF009688), // Teal
    Color(0xFF4CAF50), // Green
    Color(0xFF8BC34A), // Light Green
    Color(0xFFCDDC39), // Lime
    Color(0xFFFFEB3B), // Yellow
    Color(0xFFFFC107), // Amber
    Color(0xFFFF9800), // Orange
    Color(0xFFFF5722), // Deep Orange
    Color(0xFF795548), // Brown
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Color',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: colors.map((color) {
              final isSelected = color.value == currentColor.value;
              return GestureDetector(
                onTap: () => onColorSelected(color),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? Colors.blue : Colors.grey[400]!,
                      width: isSelected ? 3 : 1,
                    ),
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          color: color.computeLuminance() > 0.5
                              ? Colors.black
                              : Colors.white,
                        )
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
