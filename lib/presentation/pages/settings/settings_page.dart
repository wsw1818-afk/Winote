import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/note_storage_service.dart';
import '../../../core/services/pdf_export_service.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  // Default settings
  double _defaultPenWidth = 2.0;
  Color _defaultPenColor = Colors.black;
  bool _autoSaveEnabled = true;
  int _autoSaveDelay = 3;
  bool _showDebugOverlay = false;
  String _defaultTemplate = '빈 페이지';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        children: [
          // Pen Settings Section
          _buildSectionHeader('펜 설정'),
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('기본 펜 굵기'),
            subtitle: Text('${_defaultPenWidth.toStringAsFixed(1)}px'),
            trailing: SizedBox(
              width: 150,
              child: Slider(
                value: _defaultPenWidth,
                min: 0.5,
                max: 10.0,
                divisions: 19,
                label: _defaultPenWidth.toStringAsFixed(1),
                onChanged: (value) {
                  setState(() => _defaultPenWidth = value);
                },
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.color_lens),
            title: const Text('기본 펜 색상'),
            trailing: GestureDetector(
              onTap: _showColorPicker,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _defaultPenColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey[300]!),
                ),
              ),
            ),
          ),

          const Divider(),

          // Template Settings Section
          _buildSectionHeader('템플릿 설정'),
          ListTile(
            leading: const Icon(Icons.grid_on),
            title: const Text('기본 템플릿'),
            subtitle: Text(_defaultTemplate),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showTemplateOptions,
          ),

          const Divider(),

          // Auto Save Settings Section
          _buildSectionHeader('저장 설정'),
          SwitchListTile(
            secondary: const Icon(Icons.save),
            title: const Text('자동 저장'),
            subtitle: Text(_autoSaveEnabled ? '${_autoSaveDelay}초 후 자동 저장' : '꺼짐'),
            value: _autoSaveEnabled,
            onChanged: (value) {
              setState(() => _autoSaveEnabled = value);
            },
          ),
          if (_autoSaveEnabled)
            ListTile(
              leading: const SizedBox(width: 24),
              title: const Text('자동 저장 지연 시간'),
              subtitle: Text('$_autoSaveDelay초'),
              trailing: SizedBox(
                width: 150,
                child: Slider(
                  value: _autoSaveDelay.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: '$_autoSaveDelay초',
                  onChanged: (value) {
                    setState(() => _autoSaveDelay = value.toInt());
                  },
                ),
              ),
            ),

          const Divider(),

          // Storage Section
          _buildSectionHeader('저장소'),
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('노트 저장 폴더'),
            subtitle: const Text('문서/Winote/notes'),
            trailing: const Icon(Icons.folder_open),
            onTap: _openNotesFolder,
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf),
            title: const Text('PDF 내보내기 폴더'),
            subtitle: const Text('문서/Winote/exports'),
            trailing: const Icon(Icons.folder_open),
            onTap: _openExportsFolder,
          ),

          const Divider(),

          // Debug Settings Section
          _buildSectionHeader('개발자 옵션'),
          SwitchListTile(
            secondary: const Icon(Icons.bug_report),
            title: const Text('디버그 오버레이 표시'),
            subtitle: const Text('필기 입력 정보 표시'),
            value: _showDebugOverlay,
            onChanged: (value) {
              setState(() => _showDebugOverlay = value);
            },
          ),

          const Divider(),

          // About Section
          _buildSectionHeader('정보'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('앱 정보'),
            subtitle: const Text('버전 1.0.0'),
            onTap: _showAboutDialog,
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('GitHub'),
            subtitle: const Text('wsw1818-afk/Winote'),
            trailing: const Icon(Icons.open_in_new),
            onTap: _openGitHub,
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever),
            title: const Text('모든 노트 삭제'),
            subtitle: const Text('모든 데이터가 삭제됩니다'),
            trailing: const Icon(Icons.chevron_right, color: Colors.red),
            onTap: _showDeleteAllDialog,
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).primaryColor,
        ),
      ),
    );
  }

  void _showColorPicker() {
    final colors = [
      Colors.black,
      Colors.grey,
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.blue,
      Colors.purple,
      Colors.pink,
      Colors.brown,
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('기본 펜 색상'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((color) {
            final isSelected = color == _defaultPenColor;
            return GestureDetector(
              onTap: () {
                setState(() => _defaultPenColor = color);
                Navigator.pop(context);
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.blue : Colors.grey[300]!,
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
      ),
    );
  }

  void _showTemplateOptions() {
    final templates = ['빈 페이지', '줄 노트', '격자 노트', '점 노트'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('기본 템플릿'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: templates.map((template) {
            return RadioListTile<String>(
              title: Text(template),
              value: template,
              groupValue: _defaultTemplate,
              onChanged: (value) {
                setState(() => _defaultTemplate = value!);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _openNotesFolder() async {
    final storageService = NoteStorageService.instance;
    final dir = await storageService.notesDirectory;
    final uri = Uri.file(dir);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openExportsFolder() async {
    final pdfService = PdfExportService.instance;
    final dir = await pdfService.getExportsDirectory();
    final uri = Uri.file(dir);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'Winote',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.edit_note, size: 48),
      applicationLegalese: '© 2024 Winote\n\nWindows 태블릿을 위한 필기 앱',
      children: [
        const SizedBox(height: 16),
        const Text('기능:'),
        const Text('• S-Pen/손가락 구분'),
        const Text('• 필압 감지'),
        const Text('• 펜/형광펜/지우개'),
        const Text('• Undo/Redo'),
        const Text('• 줌/팬'),
        const Text('• 노트 저장/불러오기'),
        const Text('• PDF 내보내기'),
        const Text('• 여러 페이지 관리'),
      ],
    );
  }

  Future<void> _openGitHub() async {
    final uri = Uri.parse('https://github.com/wsw1818-afk/Winote');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showDeleteAllDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('모든 노트 삭제'),
        content: const Text(
          '정말로 모든 노트를 삭제하시겠습니까?\n\n이 작업은 되돌릴 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteAllNotes();
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

  Future<void> _deleteAllNotes() async {
    final storageService = NoteStorageService.instance;
    final notes = await storageService.listNotes();

    for (final note in notes) {
      await storageService.deleteNote(note.id);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${notes.length}개의 노트가 삭제되었습니다')),
      );
    }
  }
}
