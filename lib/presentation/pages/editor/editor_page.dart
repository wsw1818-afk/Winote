import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../domain/entities/stroke.dart';
import '../../widgets/canvas/drawing_canvas.dart';

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

  // 도구 상태
  ToolType _currentTool = ToolType.pen;
  Color _currentColor = Colors.black;
  double _currentWidth = 2.0;

  // 색상 프리셋
  final List<Color> _colorPresets = [
    Colors.black,
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
  ];

  // 두께 프리셋
  final List<double> _widthPresets = [1.0, 2.0, 4.0, 8.0];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.noteId == 'new' ? '새 노트' : '노트 편집'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: '실행 취소',
            onPressed: () {
              _canvasKey.currentState?.undo();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '전체 삭제',
            onPressed: () {
              _showClearConfirmDialog();
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              _showMoreMenu();
            },
          ),
        ],
      ),
      body: DrawingCanvas(
        key: _canvasKey,
        strokeColor: _currentColor,
        strokeWidth: _currentWidth,
        toolType: _currentTool,
        onStrokesChanged: (strokes) {
          // TODO: 스트로크 저장
        },
      ),
      bottomNavigationBar: _buildToolbar(),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // 도구 선택
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildToolButton(
                    icon: Icons.edit,
                    label: '펜',
                    isSelected: _currentTool == ToolType.pen,
                    onTap: () => setState(() => _currentTool = ToolType.pen),
                  ),
                  _buildToolButton(
                    icon: Icons.brush,
                    label: '마커',
                    isSelected: _currentTool == ToolType.marker,
                    onTap: () => setState(() => _currentTool = ToolType.marker),
                  ),
                  _buildToolButton(
                    icon: Icons.highlight,
                    label: '형광펜',
                    isSelected: _currentTool == ToolType.highlighter,
                    onTap: () => setState(() => _currentTool = ToolType.highlighter),
                  ),
                  _buildToolButton(
                    icon: Icons.auto_fix_high,
                    label: '지우개',
                    isSelected: _currentTool == ToolType.eraser,
                    onTap: () => setState(() => _currentTool = ToolType.eraser),
                  ),
                ],
              ),
            ),
            // 구분선
            Container(
              width: 1,
              height: 40,
              color: Colors.grey.withOpacity(0.3),
            ),
            // 색상 선택
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: GestureDetector(
                onTap: _showColorPicker,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _currentColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.grey.withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
            // 두께 선택
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: GestureDetector(
                onTap: _showWidthPicker,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.grey.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: _currentWidth * 2,
                      height: _currentWidth * 2,
                      decoration: BoxDecoration(
                        color: _currentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  void _showColorPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '색상 선택',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _colorPresets.map((color) {
                final isSelected = color == _currentColor;
                return GestureDetector(
                  onTap: () {
                    setState(() => _currentColor = color);
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withOpacity(0.5),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showWidthPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '두께 선택',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _widthPresets.map((width) {
                final isSelected = width == _currentWidth;
                return GestureDetector(
                  onTap: () {
                    setState(() => _currentWidth = width);
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: width * 3,
                        height: width * 3,
                        decoration: BoxDecoration(
                          color: _currentColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showClearConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('전체 삭제'),
        content: const Text('모든 필기를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              _canvasKey.currentState?.clear();
              Navigator.pop(context);
            },
            child: const Text('삭제'),
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
              leading: const Icon(Icons.save),
              title: const Text('저장'),
              onTap: () {
                Navigator.pop(context);
                // TODO: 저장 기능
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('저장 기능은 구현 예정입니다')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('공유'),
              onTap: () {
                Navigator.pop(context);
                // TODO: 공유 기능
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('공유 기능은 구현 예정입니다')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('노트 정보'),
              onTap: () {
                Navigator.pop(context);
                // TODO: 노트 정보 표시
              },
            ),
          ],
        ),
      ),
    );
  }
}
