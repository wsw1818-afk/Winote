import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Floating toolbar for editing selected images
class ImageEditToolbar extends StatefulWidget {
  final double rotation; // in radians
  final double opacity;
  final void Function(double) onRotationChanged;
  final void Function(double) onOpacityChanged;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  const ImageEditToolbar({
    super.key,
    required this.rotation,
    required this.opacity,
    required this.onRotationChanged,
    required this.onOpacityChanged,
    required this.onDelete,
    required this.onClose,
  });

  @override
  State<ImageEditToolbar> createState() => _ImageEditToolbarState();
}

class _ImageEditToolbarState extends State<ImageEditToolbar> {
  late double _currentRotation;
  late double _currentOpacity;

  @override
  void initState() {
    super.initState();
    _currentRotation = widget.rotation;
    _currentOpacity = widget.opacity;
  }

  @override
  void didUpdateWidget(ImageEditToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rotation != widget.rotation) {
      _currentRotation = widget.rotation;
    }
    if (oldWidget.opacity != widget.opacity) {
      _currentOpacity = widget.opacity;
    }
  }

  // Convert radians to degrees for display
  double get _rotationDegrees => _currentRotation * 180 / math.pi;

  @override
  Widget build(BuildContext context) {
    return Material(
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with close button
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.image, size: 20, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  '이미지 편집',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(width: 16),
                InkWell(
                  onTap: widget.onClose,
                  child: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Rotation control
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.rotate_right, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                const Text('회전', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 150,
                  child: Slider(
                    value: _currentRotation,
                    min: -math.pi,
                    max: math.pi,
                    onChanged: (value) {
                      setState(() => _currentRotation = value);
                      widget.onRotationChanged(value);
                    },
                  ),
                ),
                SizedBox(
                  width: 45,
                  child: Text(
                    '${_rotationDegrees.toStringAsFixed(0)}°',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),

            // Quick rotation buttons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 26),
                _QuickRotateButton(
                  label: '-90°',
                  onTap: () {
                    final newRotation = _currentRotation - math.pi / 2;
                    setState(() => _currentRotation = newRotation);
                    widget.onRotationChanged(newRotation);
                  },
                ),
                const SizedBox(width: 4),
                _QuickRotateButton(
                  label: '0°',
                  onTap: () {
                    setState(() => _currentRotation = 0);
                    widget.onRotationChanged(0);
                  },
                ),
                const SizedBox(width: 4),
                _QuickRotateButton(
                  label: '+90°',
                  onTap: () {
                    final newRotation = _currentRotation + math.pi / 2;
                    setState(() => _currentRotation = newRotation);
                    widget.onRotationChanged(newRotation);
                  },
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Opacity control
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.opacity, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                const Text('투명도', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 150,
                  child: Slider(
                    value: _currentOpacity,
                    min: 0.1,
                    max: 1.0,
                    onChanged: (value) {
                      setState(() => _currentOpacity = value);
                      widget.onOpacityChanged(value);
                    },
                  ),
                ),
                SizedBox(
                  width: 45,
                  child: Text(
                    '${(_currentOpacity * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Delete button
            InkWell(
              onTap: widget.onDelete,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete, size: 18, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Text(
                      '이미지 삭제',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickRotateButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickRotateButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11),
        ),
      ),
    );
  }
}
