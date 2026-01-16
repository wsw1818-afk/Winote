import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/note_storage_service.dart';
import '../../../domain/entities/stroke.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final NoteStorageService _storageService = NoteStorageService.instance;
  List<Note> _notes = [];
  List<Note> _filteredNotes = [];
  List<NoteFolder> _folders = [];
  String? _currentFolderId; // null = root folder
  bool _isLoading = true;
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _showFavoritesOnly = false; // 즐겨찾기 필터
  String? _selectedTag; // 선택된 태그 필터
  List<String> _allTags = []; // 모든 태그 목록

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      _filterNotes();
    });
  }

  void _filterNotes() {
    var filtered = _notes.toList();

    // 즐겨찾기 필터
    if (_showFavoritesOnly) {
      filtered = filtered.where((note) => note.isFavorite).toList();
    }

    // 태그 필터
    if (_selectedTag != null) {
      filtered = filtered.where((note) => note.tags.contains(_selectedTag)).toList();
    }

    // 검색어 필터
    if (_searchQuery.isNotEmpty) {
      final lowerQuery = _searchQuery.toLowerCase();
      filtered = filtered.where((note) {
        return note.title.toLowerCase().contains(lowerQuery);
      }).toList();
    }

    _filteredNotes = filtered;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    _folders = await _storageService.listFolders();
    _notes = await _storageService.listNotesInFolder(_currentFolderId);
    _allTags = await _storageService.getAllTags();
    _filterNotes();
    setState(() => _isLoading = false);
  }

  Future<void> _loadNotes() async {
    _notes = await _storageService.listNotesInFolder(_currentFolderId);
    _filterNotes();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final currentFolder = _folders.where((f) => f.id == _currentFolderId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '노트 검색...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.grey[400]),
                ),
                style: const TextStyle(fontSize: 18),
              )
            : Text(_currentFolderId == null ? '라이브러리' : currentFolder?.name ?? '폴더'),
        leading: IconButton(
          icon: Icon(_isSearching
              ? Icons.close
              : (_currentFolderId == null ? Icons.arrow_back : Icons.folder_open)),
          onPressed: () {
            if (_isSearching) {
              setState(() {
                _isSearching = false;
                _searchController.clear();
                _searchQuery = '';
                _filterNotes();
              });
            } else if (_currentFolderId == null) {
              context.pop();
            } else {
              // Go back to root
              setState(() => _currentFolderId = null);
              _loadNotes();
            }
          },
        ),
        actions: [
          if (!_isSearching) ...[
            // 즐겨찾기 필터 버튼
            IconButton(
              icon: Icon(
                _showFavoritesOnly ? Icons.star : Icons.star_border,
                color: _showFavoritesOnly ? Colors.amber : null,
              ),
              tooltip: _showFavoritesOnly ? '전체 노트 보기' : '즐겨찾기만 보기',
              onPressed: () {
                setState(() {
                  _showFavoritesOnly = !_showFavoritesOnly;
                  _filterNotes();
                });
              },
            ),
            // 태그 필터 버튼
            PopupMenuButton<String?>(
              icon: Icon(
                Icons.label,
                color: _selectedTag != null ? Colors.blue : null,
              ),
              tooltip: '태그 필터',
              onSelected: (tag) {
                setState(() {
                  _selectedTag = tag;
                  _filterNotes();
                });
              },
              itemBuilder: (context) => [
                PopupMenuItem<String?>(
                  value: null,
                  child: Row(
                    children: [
                      const Icon(Icons.clear, size: 20),
                      const SizedBox(width: 8),
                      const Text('전체 보기'),
                      if (_selectedTag == null) ...[
                        const Spacer(),
                        const Icon(Icons.check, size: 18, color: Colors.blue),
                      ],
                    ],
                  ),
                ),
                if (_allTags.isNotEmpty) const PopupMenuDivider(),
                ..._allTags.map((tag) => PopupMenuItem<String?>(
                      value: tag,
                      child: Row(
                        children: [
                          const Icon(Icons.label_outline, size: 20),
                          const SizedBox(width: 8),
                          Text(tag),
                          if (_selectedTag == tag) ...[
                            const Spacer(),
                            const Icon(Icons.check, size: 18, color: Colors.blue),
                          ],
                        ],
                      ),
                    )),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: '검색',
              onPressed: () {
                setState(() => _isSearching = true);
              },
            ),
            IconButton(
              icon: const Icon(Icons.create_new_folder),
              tooltip: '새 폴더',
              onPressed: _showCreateFolderDialog,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '새로고침',
              onPressed: _loadData,
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/editor/new'),
        tooltip: '새 노트',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildContent() {
    // Show search results if searching
    if (_isSearching || _searchQuery.isNotEmpty) {
      if (_filteredNotes.isEmpty) {
        return _buildNoSearchResults();
      }
      return _buildSearchResults();
    }

    if (_currentFolderId == null) {
      // Root: show folders + notes
      if (_folders.isEmpty && _filteredNotes.isEmpty) {
        return _buildEmptyState();
      }
      return _buildFoldersAndNotes();
    } else {
      // Inside folder: show only notes
      if (_filteredNotes.isEmpty) {
        return _buildEmptyFolderState();
      }
      return _buildNotesList();
    }
  }

  Widget _buildNoSearchResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '"$_searchQuery" 검색 결과 없음',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            '다른 검색어를 입력해보세요',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '검색 결과: ${_filteredNotes.length}개',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.85,
              ),
              itemCount: _filteredNotes.length,
              itemBuilder: (context, index) {
                return _buildNoteCard(_filteredNotes[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFoldersAndNotes() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: CustomScrollView(
        slivers: [
          // Folders section
          if (_folders.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  '폴더',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.2,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildFolderCard(_folders[index]),
                  childCount: _folders.length,
                ),
              ),
            ),
          ],
          // Notes section
          if (_filteredNotes.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  '노트',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.85,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildNoteCard(_filteredNotes[index]),
                  childCount: _filteredNotes.length,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFolderCard(NoteFolder folder) {
    return Card(
      elevation: 1,
      child: InkWell(
        onTap: () {
          setState(() => _currentFolderId = folder.id);
          _loadNotes();
        },
        onLongPress: () => _showFolderOptions(folder),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder,
              size: 40,
              color: Color(folder.colorValue),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                folder.name,
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyFolderState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '폴더가 비어있습니다',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
        ],
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
        itemCount: _filteredNotes.length,
        itemBuilder: (context, index) {
          final note = _filteredNotes[index];
          return _buildNoteCard(note);
        },
      ),
    );
  }

  Widget _buildNoteCard(Note note) {
    // Get first page strokes for thumbnail
    final firstPageStrokes = note.pages.isNotEmpty ? note.pages.first.strokes : note.strokes;

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
            // Preview area with actual thumbnail
            Expanded(
              child: Container(
                width: double.infinity,
                color: Colors.grey[100],
                child: firstPageStrokes.isEmpty
                    ? Center(
                        child: Icon(
                          Icons.draw_outlined,
                          size: 48,
                          color: Colors.grey[300],
                        ),
                      )
                    : ClipRect(
                        child: CustomPaint(
                          painter: _NoteThumbnailPainter(
                            strokes: firstPageStrokes,
                          ),
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
                  Row(
                    children: [
                      // 즐겨찾기 별 아이콘
                      if (note.isFavorite)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.star,
                            size: 16,
                            color: Colors.amber,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          note.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (note.pages.length > 1)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${note.pages.length}p',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 태그 표시
                  if (note.tags.isNotEmpty)
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: note.tags.take(3).map((tag) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '#$tag',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[600],
                            ),
                          ),
                        );
                      }).toList(),
                    )
                  else
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
            // 즐겨찾기 토글
            ListTile(
              leading: Icon(
                note.isFavorite ? Icons.star : Icons.star_border,
                color: note.isFavorite ? Colors.amber : null,
              ),
              title: Text(note.isFavorite ? '즐겨찾기 해제' : '즐겨찾기 추가'),
              onTap: () async {
                Navigator.pop(context);
                await _storageService.toggleFavorite(note.id);
                _loadNotes();
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
              leading: const Icon(Icons.drive_file_move),
              title: const Text('폴더로 이동'),
              onTap: () {
                Navigator.pop(context);
                _showMoveToFolderDialog(note);
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

  // ===== Folder Management =====

  void _showCreateFolderDialog() {
    final controller = TextEditingController();
    int selectedColor = 0xFF2196F3; // Default blue

    final colors = [
      0xFF2196F3, // Blue
      0xFF4CAF50, // Green
      0xFFF44336, // Red
      0xFFFF9800, // Orange
      0xFF9C27B0, // Purple
      0xFF795548, // Brown
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('새 폴더'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '폴더 이름',
                  border: OutlineInputBorder(),
                  hintText: '예: 수학, 영어, 과학',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: colors.map((color) {
                  final isSelected = selectedColor == color;
                  return GestureDetector(
                    onTap: () => setDialogState(() => selectedColor = color),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(color),
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: Colors.black, width: 3)
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white, size: 20)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () async {
                if (controller.text.isNotEmpty) {
                  await _storageService.createFolder(
                    controller.text,
                    colorValue: selectedColor,
                  );
                  if (mounted) {
                    Navigator.pop(context);
                    _loadData();
                  }
                }
              },
              child: const Text('만들기'),
            ),
          ],
        ),
      ),
    );
  }

  void _showFolderOptions(NoteFolder folder) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('열기'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentFolderId = folder.id);
                _loadNotes();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('이름 변경'),
              onTap: () {
                Navigator.pop(context);
                _showRenameFolderDialog(folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('삭제', style: TextStyle(color: Colors.red)),
              subtitle: const Text('노트는 삭제되지 않습니다'),
              onTap: () async {
                Navigator.pop(context);
                await _storageService.deleteFolder(folder.id);
                _loadData();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameFolderDialog(NoteFolder folder) {
    final controller = TextEditingController(text: folder.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('폴더 이름 변경'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '폴더 이름',
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
                await _storageService.updateFolder(
                  folder.copyWith(name: controller.text),
                );
                if (mounted) {
                  Navigator.pop(context);
                  _loadData();
                }
              }
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _showMoveToFolderDialog(Note note) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('폴더로 이동'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Root folder option
              ListTile(
                leading: const Icon(Icons.home),
                title: const Text('라이브러리 (루트)'),
                selected: note.folderId == null,
                onTap: () async {
                  await _storageService.moveNoteToFolder(note.id, null);
                  if (mounted) {
                    Navigator.pop(context);
                    _loadNotes();
                  }
                },
              ),
              const Divider(),
              // Folder list
              ..._folders.map((folder) => ListTile(
                leading: Icon(Icons.folder, color: Color(folder.colorValue)),
                title: Text(folder.name),
                selected: note.folderId == folder.id,
                onTap: () async {
                  await _storageService.moveNoteToFolder(note.id, folder.id);
                  if (mounted) {
                    Navigator.pop(context);
                    _loadNotes();
                  }
                },
              )),
            ],
          ),
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
}

/// Custom painter for note thumbnail preview
class _NoteThumbnailPainter extends CustomPainter {
  final List<Stroke> strokes;

  _NoteThumbnailPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;

    // Calculate bounding box of all strokes
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

    // Add padding
    const padding = 10.0;
    minX -= padding;
    minY -= padding;
    maxX += padding;
    maxY += padding;

    // Calculate scale to fit in thumbnail
    final contentWidth = maxX - minX;
    final contentHeight = maxY - minY;

    if (contentWidth <= 0 || contentHeight <= 0) return;

    final scaleX = size.width / contentWidth;
    final scaleY = size.height / contentHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    // Center the content
    final offsetX = (size.width - contentWidth * scale) / 2 - minX * scale;
    final offsetY = (size.height - contentHeight * scale) / 2 - minY * scale;

    // Draw each stroke
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;

      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = (stroke.width * scale).clamp(0.5, 3.0)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (stroke.points.length == 1) {
        // Single point - draw circle
        final p = stroke.points.first;
        canvas.drawCircle(
          Offset(p.x * scale + offsetX, p.y * scale + offsetY),
          paint.strokeWidth / 2,
          paint,
        );
      } else {
        // Multiple points - draw path
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
  bool shouldRepaint(covariant _NoteThumbnailPainter oldDelegate) {
    return strokes.length != oldDelegate.strokes.length;
  }
}
