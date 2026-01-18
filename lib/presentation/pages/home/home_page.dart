import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/note_storage_service.dart';
import '../../../core/services/pdf_import_service.dart';
import '../../../domain/entities/stroke.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final NoteStorageService _storageService = NoteStorageService.instance;
  List<Note> _recentNotes = [];
  List<Note> _favoriteNotes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final allNotes = await _storageService.listNotes();

    // 최근 노트: 수정일 기준 최신 5개
    _recentNotes = allNotes.take(5).toList();

    // 즐겨찾기 노트
    _favoriteNotes = allNotes.where((n) => n.isFavorite).take(5).toList();

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Winote'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              context.push('/library');
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: _buildContent(),
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // PDF 가져오기 버튼
          FloatingActionButton.small(
            heroTag: 'importPdf',
            onPressed: _importPdf,
            tooltip: 'PDF 가져오기',
            child: const Icon(Icons.picture_as_pdf),
          ),
          const SizedBox(height: 12),
          // 새 노트 버튼
          FloatingActionButton.extended(
            heroTag: 'newNote',
            onPressed: () async {
              await context.push('/editor/new');
              _loadData();
            },
            icon: const Icon(Icons.add),
            label: const Text('새 노트'),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              // 이미 홈
              break;
            case 1:
              context.push('/library');
              break;
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '홈',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: '라이브러리',
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    // 노트가 없으면 빈 상태 표시
    if (_recentNotes.isEmpty && _favoriteNotes.isEmpty) {
      return _buildEmptyState();
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            _buildHeader(),
            const SizedBox(height: 24),

            // 즐겨찾기 노트 섹션
            if (_favoriteNotes.isNotEmpty) ...[
              _buildSectionHeader('즐겨찾기', Icons.star, Colors.amber),
              const SizedBox(height: 12),
              _buildHorizontalNoteList(_favoriteNotes),
              const SizedBox(height: 24),
            ],

            // 최근 노트 섹션
            _buildSectionHeader('최근 노트', Icons.access_time, Colors.blue),
            const SizedBox(height: 12),
            _buildRecentNotesList(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade400, Colors.blue.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_note, size: 48, color: Colors.white),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Winote',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '펜이 주인공인 필기 앱',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        if (title == '최근 노트')
          TextButton(
            onPressed: () => context.push('/library'),
            child: const Text('전체 보기'),
          ),
      ],
    );
  }

  Widget _buildHorizontalNoteList(List<Note> notes) {
    return SizedBox(
      height: 140,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: notes.length,
        itemBuilder: (context, index) {
          final note = notes[index];
          return _buildCompactNoteCard(note);
        },
      ),
    );
  }

  Widget _buildCompactNoteCard(Note note) {
    final firstPageStrokes =
        note.pages.isNotEmpty ? note.pages.first.strokes : note.strokes;

    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        child: InkWell(
          onTap: () async {
            await context.push('/editor/${note.id}');
            _loadData();
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 미리보기
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: Colors.grey[100],
                  child: firstPageStrokes.isEmpty
                      ? Center(
                          child: Icon(
                            Icons.draw_outlined,
                            size: 32,
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
              // 제목
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    if (note.isFavorite)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.star, size: 14, color: Colors.amber),
                      ),
                    Expanded(
                      child: Text(
                        note.title,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentNotesList() {
    return Column(
      children: _recentNotes.map((note) => _buildRecentNoteItem(note)).toList(),
    );
  }

  Widget _buildRecentNoteItem(Note note) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () async {
          await context.push('/editor/${note.id}');
          _loadData();
        },
        onLongPress: () => _showDeleteNoteDialog(note),
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: note.strokes.isEmpty
                ? Icon(Icons.draw_outlined, color: Colors.grey[400])
                : ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CustomPaint(
                      painter: _NoteThumbnailPainter(
                        strokes: note.pages.isNotEmpty
                            ? note.pages.first.strokes
                            : note.strokes,
                      ),
                    ),
                  ),
          ),
          title: Row(
            children: [
              if (note.isFavorite)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.star, size: 16, color: Colors.amber),
                ),
              Expanded(
                child: Text(
                  note.title,
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
          subtitle: Text(
            _formatDate(note.modifiedAt),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }

  /// PDF 파일 가져오기
  Future<void> _importPdf() async {
    try {
      // PDF 파일 선택
      final pdfPath = await PdfImportService.instance.pickPdfFile();
      if (pdfPath == null) return;

      // 로딩 표시
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('PDF 가져오는 중...'),
              ],
            ),
          ),
        );
      }

      // PDF를 노트로 변환
      final note = await PdfImportService.instance.importPdfWithMultiplePages(
        pdfPath: pdfPath,
      );

      // 로딩 닫기
      if (mounted) Navigator.pop(context);

      if (note != null) {
        // 노트 저장
        await _storageService.saveNote(note);

        // 에디터로 이동
        if (mounted) {
          await context.push('/editor/${note.id}');
          _loadData();
        }
      } else {
        // 오류 메시지
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PDF 가져오기에 실패했습니다')),
          );
        }
      }
    } catch (e) {
      debugPrint('PDF 가져오기 오류: $e');
      if (mounted) {
        Navigator.pop(context); // 로딩 닫기
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e')),
        );
      }
    }
  }

  void _showDeleteNoteDialog(Note note) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('노트 삭제'),
        content: Text('"${note.title}" 노트를 삭제하시겠습니까?\n\n삭제된 노트는 복구할 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _storageService.deleteNote(note.id);
              _loadData();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
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
            Icons.edit_note,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            '아직 노트가 없습니다',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '아래 버튼을 눌러 첫 번째 노트를 만들어보세요!',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
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
