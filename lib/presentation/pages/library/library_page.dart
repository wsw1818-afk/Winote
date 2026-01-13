import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/note_storage_service.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final NoteStorageService _storageService = NoteStorageService.instance;
  List<Note> _notes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    setState(() => _isLoading = true);
    _notes = await _storageService.listNotes();
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('라이브러리'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: _loadNotes,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
              ? _buildEmptyState()
              : _buildNotesList(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/editor/new'),
        tooltip: '새 노트',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.note_alt_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '저장된 노트가 없습니다',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '+ 버튼을 눌러 새 노트를 만드세요',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesList() {
    return RefreshIndicator(
      onRefresh: _loadNotes,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.85,
        ),
        itemCount: _notes.length,
        itemBuilder: (context, index) {
          final note = _notes[index];
          return _buildNoteCard(note);
        },
      ),
    );
  }

  Widget _buildNoteCard(Note note) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: () async {
          await context.push('/editor/${note.id}');
          // Refresh list when returning from editor
          _loadNotes();
        },
        onLongPress: () => _showNoteOptions(note),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview area
            Expanded(
              child: Container(
                width: double.infinity,
                color: Colors.grey[100],
                child: note.strokes.isEmpty
                    ? Center(
                        child: Icon(
                          Icons.draw_outlined,
                          size: 48,
                          color: Colors.grey[300],
                        ),
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.edit_note,
                              size: 40,
                              color: Colors.blue[300],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${note.strokes.length}개 스트로크',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            // Info area
            Container(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(note.modifiedAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) {
      return '방금 전';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}분 전';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}시간 전';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}일 전';
    } else {
      return '${date.month}/${date.day}';
    }
  }

  void _showNoteOptions(Note note) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('열기'),
              onTap: () {
                Navigator.pop(context);
                context.push('/editor/${note.id}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('이름 변경'),
              onTap: () {
                Navigator.pop(context);
                _showRenameDialog(note);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('삭제', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirmDialog(note);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(Note note) {
    final controller = TextEditingController(text: note.title);

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
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final updatedNote = note.copyWith(
                  title: controller.text,
                  modifiedAt: DateTime.now(),
                );
                await _storageService.saveNote(updatedNote);
                if (mounted) {
                  Navigator.pop(context);
                  _loadNotes();
                }
              }
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(Note note) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('노트 삭제'),
        content: Text('"${note.title}"을(를) 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              await _storageService.deleteNote(note.id);
              if (mounted) {
                Navigator.pop(context);
                _loadNotes();
              }
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
}
