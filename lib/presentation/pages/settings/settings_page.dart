import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/services/note_storage_service.dart';
import '../../../core/services/pdf_export_service.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/providers/drawing_state.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  // Default settings
  Color _lassoColor = const Color(0xFF2196F3); // Blue
  bool _autoSaveEnabled = true;
  int _autoSaveDelay = 3;
  bool _showDebugOverlay = false;
  String _defaultTemplate = '빈 페이지';
  // Gesture settings
  String _twoFingerGestureMode = 'zoom'; // 'zoom' or 'scroll'
  bool _palmRejectionEnabled = true;
  int _palmRejectionGracePeriod = 1000; // 밀리초
  bool _touchDrawingEnabled = false;
  // Shape snap settings
  bool _shapeSnapEnabled = true;
  double _shapeSnapAngle = 15.0;
  // 필압 민감도
  double _pressureSensitivity = 0.6;
  // 3손가락 제스처
  bool _threeFingerGestureEnabled = true;
  // S펜 호버 커서
  bool _penHoverCursorEnabled = true;

  // UI/UX 모드
  bool _fullscreenModeEnabled = false;
  bool _darkCanvasModeEnabled = false;
  bool _leftHandedModeEnabled = false;

  // Cloud sync settings
  final CloudSyncService _cloudSync = CloudSyncService.instance;
  bool _isSyncing = false;
  bool _autoSyncEnabled = false;
  bool _realtimeSyncEnabled = false;
  bool _fileWatchEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initCloudSync();
  }

  Future<void> _initCloudSync() async {
    await _cloudSync.initialize();
    if (mounted) {
      setState(() {
        _realtimeSyncEnabled = _cloudSync.isRealtimeSyncEnabled;
        _fileWatchEnabled = _cloudSync.isFileWatchEnabled;
      });
    }
  }

  Future<void> _loadSettings() async {
    final settings = SettingsService.instance;
    setState(() {
      _lassoColor = settings.lassoColor;
      _autoSaveEnabled = settings.autoSaveEnabled;
      _autoSaveDelay = settings.autoSaveDelay;
      _defaultTemplate = _templateToString(settings.defaultTemplate);
      _showDebugOverlay = settings.showDebugOverlay;
      _twoFingerGestureMode = settings.twoFingerGestureMode;
      _palmRejectionEnabled = settings.palmRejectionEnabled;
      _palmRejectionGracePeriod = settings.palmRejectionGracePeriod;
      _touchDrawingEnabled = settings.touchDrawingEnabled;
      _shapeSnapEnabled = settings.shapeSnapEnabled;
      _shapeSnapAngle = settings.shapeSnapAngle;
      _pressureSensitivity = settings.pressureSensitivity;
      _threeFingerGestureEnabled = settings.threeFingerGestureEnabled;
      _penHoverCursorEnabled = settings.penHoverCursorEnabled;
      _autoSyncEnabled = settings.autoSyncEnabled;
      // UI/UX 모드
      _fullscreenModeEnabled = settings.fullscreenModeEnabled;
      _darkCanvasModeEnabled = settings.darkCanvasModeEnabled;
      _leftHandedModeEnabled = settings.leftHandedModeEnabled;
    });
  }

  String _templateToString(dynamic template) {
    if (template.toString().contains('blank')) return '빈 페이지';
    if (template.toString().contains('lined')) return '줄 노트';
    if (template.toString().contains('grid')) return '격자 노트';
    if (template.toString().contains('dotted')) return '점 노트';
    return '빈 페이지';
  }

  String _getPressureSensitivityLabel(double sensitivity) {
    if (sensitivity <= 0.4) return '부드러움 (가벼운 터치)';
    if (sensitivity <= 0.5) return '약간 부드러움';
    if (sensitivity <= 0.6) return '보통';
    if (sensitivity <= 0.7) return '약간 강함';
    if (sensitivity <= 0.8) return '강함';
    return '매우 강함 (힘줘야 굵어짐)';
  }

  String _getPalmRejectionGracePeriodLabel(int ms) {
    if (ms <= 500) return '짧게 (${ms}ms)';
    if (ms <= 1000) return '보통 (${ms}ms)';
    if (ms <= 1500) return '길게 (${ms}ms)';
    return '매우 길게 (${ms}ms)';
  }

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
          // Lasso Settings Section
          _buildSectionHeader('올가미 설정'),
          ListTile(
            leading: const Icon(Icons.gesture),
            title: const Text('올가미 선 색상'),
            subtitle: const Text('영역 선택 시 표시되는 선 색상'),
            trailing: GestureDetector(
              onTap: _showLassoColorPicker,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _lassoColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey[300]!),
                ),
              ),
            ),
          ),

          const Divider(),

          // Gesture Settings Section
          _buildSectionHeader('제스처 설정'),
          ListTile(
            leading: const Icon(Icons.touch_app),
            title: const Text('두 손가락 제스처'),
            subtitle: Text(_twoFingerGestureMode == 'zoom' ? '확대/축소' : '스크롤'),
            trailing: SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(value: 'zoom', label: Text('줌')),
                ButtonSegment<String>(value: 'scroll', label: Text('스크롤')),
              ],
              selected: {_twoFingerGestureMode},
              onSelectionChanged: (Set<String> newSelection) async {
                setState(() => _twoFingerGestureMode = newSelection.first);
                await SettingsService.instance.setTwoFingerGestureMode(newSelection.first);
              },
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.pan_tool),
            title: const Text('손바닥 무시'),
            subtitle: const Text('펜 사용 시 손바닥 터치 무시'),
            value: _palmRejectionEnabled,
            onChanged: (value) async {
              setState(() => _palmRejectionEnabled = value);
              await SettingsService.instance.setPalmRejectionEnabled(value);
            },
          ),
          if (_palmRejectionEnabled)
            ListTile(
              leading: const Icon(Icons.timer),
              title: const Text('터치 무시 시간'),
              subtitle: Text(_getPalmRejectionGracePeriodLabel(_palmRejectionGracePeriod)),
              trailing: SizedBox(
                width: 180,
                child: Slider(
                  value: _palmRejectionGracePeriod.toDouble(),
                  min: 200,
                  max: 3000,
                  divisions: 14,
                  label: '${_palmRejectionGracePeriod}ms',
                  onChanged: (value) async {
                    setState(() => _palmRejectionGracePeriod = value.toInt());
                    await SettingsService.instance.setPalmRejectionGracePeriod(value.toInt());
                  },
                ),
              ),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('손으로 그리기'),
            subtitle: const Text('펜 없이 손가락으로 그리기 허용'),
            value: _touchDrawingEnabled,
            onChanged: (value) async {
              setState(() => _touchDrawingEnabled = value);
              await SettingsService.instance.setTouchDrawingEnabled(value);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.swipe),
            title: const Text('3손가락 제스처'),
            subtitle: const Text('3손가락 탭=다시실행, 스와이프=실행취소/다시실행'),
            value: _threeFingerGestureEnabled,
            onChanged: (value) async {
              setState(() => _threeFingerGestureEnabled = value);
              await SettingsService.instance.setThreeFingerGestureEnabled(value);
            },
          ),

          const Divider(),

          // 펜 설정 섹션
          _buildSectionHeader('펜 설정'),
          SwitchListTile(
            secondary: const Icon(Icons.mouse),
            title: const Text('호버 커서 표시'),
            subtitle: const Text('S펜을 화면에 가까이 대면 커서 미리보기'),
            value: _penHoverCursorEnabled,
            onChanged: (value) async {
              setState(() => _penHoverCursorEnabled = value);
              await SettingsService.instance.setPenHoverCursorEnabled(value);
            },
          ),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('필압 민감도'),
            subtitle: Text(_getPressureSensitivityLabel(_pressureSensitivity)),
            trailing: SizedBox(
              width: 180,
              child: Slider(
                value: _pressureSensitivity,
                min: 0.3,
                max: 1.0,
                divisions: 7,
                label: _getPressureSensitivityLabel(_pressureSensitivity),
                onChanged: (value) async {
                  setState(() => _pressureSensitivity = value);
                  await SettingsService.instance.setPressureSensitivity(value);
                },
              ),
            ),
          ),

          const Divider(),

          // Shape Settings Section
          _buildSectionHeader('도형 설정'),
          SwitchListTile(
            secondary: const Icon(Icons.straighten),
            title: const Text('각도 스냅'),
            subtitle: Text(_shapeSnapEnabled ? '${_shapeSnapAngle.toInt()}° 단위로 스냅' : '꺼짐'),
            value: _shapeSnapEnabled,
            onChanged: (value) async {
              setState(() => _shapeSnapEnabled = value);
              await SettingsService.instance.setShapeSnapEnabled(value);
            },
          ),
          if (_shapeSnapEnabled)
            ListTile(
              leading: const Icon(Icons.rotate_90_degrees_ccw),
              title: const Text('스냅 각도'),
              subtitle: Text('${_shapeSnapAngle.toInt()}°'),
              trailing: SizedBox(
                width: 150,
                child: Slider(
                  value: _shapeSnapAngle,
                  min: 5,
                  max: 45,
                  divisions: 8,
                  label: '${_shapeSnapAngle.toInt()}°',
                  onChanged: (value) async {
                    setState(() => _shapeSnapAngle = value);
                    await SettingsService.instance.setShapeSnapAngle(value);
                  },
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
            subtitle: Text(_autoSaveEnabled ? '$_autoSaveDelay초 후 자동 저장' : '꺼짐'),
            value: _autoSaveEnabled,
            onChanged: (value) async {
              setState(() => _autoSaveEnabled = value);
              await SettingsService.instance.setAutoSaveEnabled(value);
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
                  onChanged: (value) async {
                    setState(() => _autoSaveDelay = value.toInt());
                    await SettingsService.instance.setAutoSaveDelay(value.toInt());
                  },
                ),
              ),
            ),

          const Divider(),

          // Display Settings Section
          _buildSectionHeader('화면'),
          _buildThemeSelector(),

          const Divider(),

          // UI/UX Settings Section
          _buildSectionHeader('UI/UX'),
          SwitchListTile(
            secondary: const Icon(Icons.fullscreen),
            title: const Text('풀스크린 모드'),
            subtitle: const Text('도구바를 숨기고 캔버스만 표시'),
            value: _fullscreenModeEnabled,
            onChanged: (value) async {
              setState(() => _fullscreenModeEnabled = value);
              await SettingsService.instance.setFullscreenModeEnabled(value);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode),
            title: const Text('다크 캔버스'),
            subtitle: const Text('검은 배경에 밝은 라인 (야간 필기)'),
            value: _darkCanvasModeEnabled,
            onChanged: (value) async {
              setState(() => _darkCanvasModeEnabled = value);
              await SettingsService.instance.setDarkCanvasModeEnabled(value);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.swap_horiz),
            title: const Text('왼손잡이 모드'),
            subtitle: const Text('도구바를 오른쪽에 배치'),
            value: _leftHandedModeEnabled,
            onChanged: (value) async {
              setState(() => _leftHandedModeEnabled = value);
              await SettingsService.instance.setLeftHandedModeEnabled(value);
            },
          ),

          const Divider(),

          // Cloud Sync Section
          _buildSectionHeader('클라우드 동기화'),
          ListTile(
            leading: Icon(
              _cloudSync.isEnabled ? Icons.cloud_done : Icons.cloud_off,
              color: _cloudSync.isEnabled ? Colors.green : Colors.grey,
            ),
            title: const Text('동기화 상태'),
            subtitle: Text(_cloudSync.isEnabled
                ? '${_cloudSync.provider == CloudProvider.oneDrive ? 'OneDrive' : '로컬 폴더'}와 동기화 중\n${_cloudSync.getStatusText()}'
                : '동기화 비활성화',),
            trailing: _isSyncing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_cloudSync.isEnabled ? Icons.sync : Icons.chevron_right),
            onTap: _cloudSync.isEnabled ? _syncNow : null,
          ),
          ListTile(
            leading: const Icon(Icons.cloud_upload),
            title: const Text('OneDrive 연결'),
            subtitle: Text(_cloudSync.provider == CloudProvider.oneDrive
                ? _cloudSync.syncPath ?? '설정됨'
                : '클릭하여 설정',),
            trailing: const Icon(Icons.chevron_right),
            onTap: _setupOneDrive,
          ),
          ListTile(
            leading: const Icon(Icons.folder_special),
            title: const Text('로컬 폴더 동기화'),
            subtitle: Text(_cloudSync.provider == CloudProvider.local
                ? _cloudSync.syncPath ?? '설정됨'
                : '클릭하여 설정',),
            trailing: const Icon(Icons.chevron_right),
            onTap: _setupLocalSync,
          ),
          if (_cloudSync.isEnabled) ...[
            SwitchListTile(
              secondary: const Icon(Icons.sync),
              title: const Text('실시간 동기화'),
              subtitle: const Text('노트 저장 시 즉시 클라우드에 업로드'),
              value: _realtimeSyncEnabled,
              onChanged: (value) async {
                setState(() => _realtimeSyncEnabled = value);
                await _cloudSync.setRealtimeSync(value);
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.visibility),
              title: const Text('파일 감시'),
              subtitle: const Text('클라우드 폴더 변경 감지 (자동 다운로드)'),
              value: _fileWatchEnabled,
              onChanged: (value) async {
                setState(() => _fileWatchEnabled = value);
                await _cloudSync.setFileWatch(value);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_off, color: Colors.red),
              title: const Text('동기화 해제', style: TextStyle(color: Colors.red)),
              onTap: _disableSync,
            ),
          ],

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

          // Backup Section (통합)
          _buildSectionHeader('백업'),
          ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('백업 만들기'),
            subtitle: const Text('모든 노트와 폴더를 백업'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showBackupOptions,
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('백업 복원'),
            subtitle: const Text('백업에서 노트 복원'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showRestoreOptions,
          ),
          ListTile(
            leading: const Icon(Icons.note_add),
            title: const Text('노트 가져오기'),
            subtitle: const Text('.wnote 파일 가져오기'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _importNote,
          ),
          ListTile(
            leading: const Icon(Icons.folder_special),
            title: const Text('백업 폴더 열기'),
            subtitle: const Text('문서/Winote/backups'),
            trailing: const Icon(Icons.folder_open),
            onTap: _openBackupFolder,
          ),

          const Divider(),

          // Debug Settings Section
          _buildSectionHeader('개발자 옵션'),
          SwitchListTile(
            secondary: const Icon(Icons.bug_report),
            title: const Text('디버그 오버레이 표시'),
            subtitle: const Text('필기 입력 정보 표시 (개발자용)'),
            value: _showDebugOverlay,
            onChanged: (value) async {
              setState(() => _showDebugOverlay = value);
              await SettingsService.instance.setShowDebugOverlay(value);
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

  Widget _buildThemeSelector() {
    final themeMode = ref.watch(themeModeProvider);

    String themeName;
    IconData themeIcon;
    switch (themeMode) {
      case ThemeMode.light:
        themeName = '라이트 모드';
        themeIcon = Icons.light_mode;
        break;
      case ThemeMode.dark:
        themeName = '다크 모드';
        themeIcon = Icons.dark_mode;
        break;
      default:
        themeName = '시스템 설정';
        themeIcon = Icons.brightness_auto;
    }

    return ListTile(
      leading: Icon(themeIcon),
      title: const Text('테마'),
      subtitle: Text(themeName),
      trailing: const Icon(Icons.chevron_right),
      onTap: _showThemeDialog,
    );
  }

  void _showThemeDialog() {
    final themeMode = ref.read(themeModeProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('테마 선택'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('시스템 설정'),
              subtitle: const Text('기기 설정에 따라 자동 변경'),
              secondary: const Icon(Icons.brightness_auto),
              value: ThemeMode.system,
              groupValue: themeMode,
              onChanged: (value) {
                ref.read(themeModeProvider.notifier).setThemeMode(value!);
                Navigator.pop(context);
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('라이트 모드'),
              subtitle: const Text('밝은 테마'),
              secondary: const Icon(Icons.light_mode),
              value: ThemeMode.light,
              groupValue: themeMode,
              onChanged: (value) {
                ref.read(themeModeProvider.notifier).setThemeMode(value!);
                Navigator.pop(context);
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('다크 모드'),
              subtitle: const Text('어두운 테마 (눈 보호)'),
              secondary: const Icon(Icons.dark_mode),
              value: ThemeMode.dark,
              groupValue: themeMode,
              onChanged: (value) {
                ref.read(themeModeProvider.notifier).setThemeMode(value!);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showLassoColorPicker() {
    final colors = [
      const Color(0xFF2196F3), // Blue (default)
      const Color(0xFFE91E63), // Pink
      const Color(0xFF9C27B0), // Purple
      const Color(0xFF00BCD4), // Cyan
      const Color(0xFF4CAF50), // Green
      const Color(0xFFFF9800), // Orange
      const Color(0xFFF44336), // Red
      const Color(0xFF607D8B), // Blue Grey
      Colors.black,
      const Color(0xFF795548), // Brown
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('올가미 선 색상'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((color) {
            final isSelected = color.value == _lassoColor.value;
            return GestureDetector(
              onTap: () async {
                setState(() => _lassoColor = color);
                await SettingsService.instance.setLassoColor(color);
                if (mounted) Navigator.pop(context);
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.grey[300]!,
                    width: isSelected ? 3 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
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
              onChanged: (value) async {
                setState(() => _defaultTemplate = value!);
                Navigator.pop(context);
                // Save to settings
                final pageTemplate = _stringToTemplate(value!);
                await SettingsService.instance.setDefaultTemplate(pageTemplate);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  dynamic _stringToTemplate(String name) {
    switch (name) {
      case '빈 페이지':
        return PageTemplate.blank;
      case '줄 노트':
        return PageTemplate.lined;
      case '격자 노트':
        return PageTemplate.grid;
      case '점 노트':
        return PageTemplate.dotted;
      default:
        return PageTemplate.blank;
    }
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

  Future<void> _openBackupFolder() async {
    final backupService = BackupService.instance;
    final dir = await backupService.getBackupDirectory();
    final uri = Uri.file(dir);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  /// 백업 만들기 옵션 표시 (앱 내부 / 외부 폴더)
  Future<void> _showBackupOptions() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('백업 만들기'),
        content: const Text('백업을 어디에 저장할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'external'),
            child: const Text('폴더 선택'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'internal'),
            child: const Text('앱 내부'),
          ),
        ],
      ),
    );

    if (choice == 'internal') {
      await _createBackup();
    } else if (choice == 'external') {
      await _exportBackupToExternal();
    }
  }

  /// 백업 복원 옵션 표시 (앱 내부 / 외부 파일)
  Future<void> _showRestoreOptions() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('백업 복원'),
        content: const Text('어디에서 백업을 불러올까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'external'),
            child: const Text('파일 선택'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'internal'),
            child: const Text('백업 목록'),
          ),
        ],
      ),
    );

    if (choice == 'internal') {
      await _showBackupList();
    } else if (choice == 'external') {
      await _importBackupFromExternal();
    }
  }

  Future<void> _createBackup() async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('백업 생성 중...'),
          ],
        ),
      ),
    );

    final backupService = BackupService.instance;
    final filePath = await backupService.createBackup();

    if (mounted) Navigator.pop(context);

    if (filePath != null) {
      debugPrint('백업 완료: ${filePath.split('/').last}');
    } else {
      debugPrint('백업할 데이터가 없거나 백업에 실패했습니다');
    }
  }

  Future<void> _showBackupList() async {
    final backupService = BackupService.instance;
    final backups = await backupService.listBackups();

    if (!mounted) return;

    if (backups.isEmpty) {
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.restore),
                  const SizedBox(width: 8),
                  const Text(
                    '백업 목록',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: backups.length,
                itemBuilder: (context, index) {
                  final backup = backups[index];
                  return ListTile(
                    leading: const Icon(Icons.archive),
                    title: Text(backup.fileName),
                    subtitle: Text(
                      '${_formatBackupDate(backup.createdAt)} • '
                      '노트 ${backup.noteCount}개, 폴더 ${backup.folderCount}개 • '
                      '${backupService.formatFileSize(backup.fileSize)}',
                    ),
                    trailing: PopupMenuButton<String>(
                      tooltip: '', // 기본 "Show menu" 툴팁 비활성화
                      onSelected: (action) async {
                        if (action == 'restore') {
                          Navigator.pop(context);
                          await _restoreBackup(backup);
                        } else if (action == 'delete') {
                          await _deleteBackup(backup);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'restore',
                          child: Row(
                            children: [
                              Icon(Icons.restore),
                              SizedBox(width: 8),
                              Text('복원'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red),
                              SizedBox(width: 8),
                              Text('삭제', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _restoreBackup(backup);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBackupDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return '오늘 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return '어제';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}일 전';
    } else {
      return '${date.month}/${date.day}';
    }
  }

  Future<void> _restoreBackup(BackupInfo backup) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('백업 복원'),
        content: Text(
          '이 백업을 복원하시겠습니까?\n\n'
          '${backup.fileName}\n'
          '노트 ${backup.noteCount}개, 폴더 ${backup.folderCount}개\n\n'
          '기존 노트와 중복되는 경우 덮어씁니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('복원'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Show loading
    final navigator = Navigator.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('복원 중...'),
          ],
        ),
      ),
    );

    final backupService = BackupService.instance;
    final result = await backupService.restoreBackup(backup.filePath);

    if (mounted) navigator.pop();

    debugPrint('복원 결과: ${result.message}');
  }

  Future<void> _deleteBackup(BackupInfo backup) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('백업 삭제'),
        content: Text('${backup.fileName}을(를) 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final backupService = BackupService.instance;
    final deleted = await backupService.deleteBackup(backup.filePath);

    if (mounted) {
      Navigator.pop(context); // Close bottom sheet
    }
    debugPrint(deleted ? '백업이 삭제되었습니다' : '백업 삭제 실패');
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

    debugPrint('${notes.length}개의 노트가 삭제되었습니다');
  }

  Future<void> _exportBackupToExternal() async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('백업 내보내기 중...'),
          ],
        ),
      ),
    );

    final backupService = BackupService.instance;
    final result = await backupService.exportBackupToExternal();

    if (mounted) Navigator.pop(context);

    if (result != null) {
      debugPrint('백업 내보내기 완료: ${result.split('\\').last}');
    } else {
      debugPrint('백업 내보내기가 취소되었거나 실패했습니다');
    }
  }

  Future<void> _importBackupFromExternal() async {
    final backupService = BackupService.instance;
    final result = await backupService.importBackupFromExternal();

    debugPrint('가져오기 결과: ${result.message}');
  }

  Future<void> _shareBackup() async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('공유 준비 중...'),
          ],
        ),
      ),
    );

    final backupService = BackupService.instance;
    final success = await backupService.shareBackup(null);

    if (mounted) Navigator.pop(context);

    if (!success) {
      debugPrint('공유할 데이터가 없거나 공유에 실패했습니다');
    }
  }

  Future<void> _importNote() async {
    final backupService = BackupService.instance;
    final note = await backupService.importNote();

    if (note != null) {
      debugPrint('노트 가져오기 완료: ${note.title}');
    } else {
      debugPrint('노트 가져오기가 취소되었거나 실패했습니다');
    }
  }

  // ===== Cloud Sync Methods =====

  Future<void> _syncNow() async {
    if (_isSyncing) return;

    setState(() => _isSyncing = true);

    final result = await _cloudSync.syncAll();

    if (mounted) {
      setState(() => _isSyncing = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _setupOneDrive() async {
    // OneDrive 경로 자동 감지
    final oneDrivePath = await _cloudSync.detectOneDrivePath();

    if (oneDrivePath != null) {
      // 자동 감지 또는 직접 선택 옵션 제공
      final navigator = Navigator.of(context);
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('OneDrive 연결'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('OneDrive 폴더를 찾았습니다:'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  oneDrivePath,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 16),
              const Text('어떻게 하시겠습니까?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'select'),
              child: const Text('직접 선택'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'auto'),
              child: const Text('이 폴더 사용'),
            ),
          ],
        ),
      );

      if (choice == 'auto') {
        final success = await _cloudSync.setSyncFolder(oneDrivePath, CloudProvider.oneDrive);
        if (mounted) {
          setState(() {
            _realtimeSyncEnabled = _cloudSync.isRealtimeSyncEnabled;
            _fileWatchEnabled = _cloudSync.isFileWatchEnabled;
          });
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('OneDrive 연결 완료')),
            );
          }
        }
      } else if (choice == 'select') {
        await _selectSyncFolder(CloudProvider.oneDrive);
      }
    } else {
      // OneDrive를 찾지 못한 경우 수동 선택
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OneDrive 폴더를 찾을 수 없습니다. 수동으로 선택해주세요.'),
            duration: Duration(seconds: 3),
          ),
        );
        await _selectSyncFolder(CloudProvider.oneDrive);
      }
    }
  }

  Future<void> _setupLocalSync() async {
    await _selectSyncFolder(CloudProvider.local);
  }

  Future<void> _selectSyncFolder(CloudProvider provider) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: provider == CloudProvider.oneDrive
          ? 'OneDrive 폴더 선택'
          : '동기화 폴더 선택',
    );

    if (result != null) {
      final success = await _cloudSync.setSyncFolder(result, provider);
      if (mounted) {
        setState(() {
          _realtimeSyncEnabled = _cloudSync.isRealtimeSyncEnabled;
          _fileWatchEnabled = _cloudSync.isFileWatchEnabled;
        });
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${provider == CloudProvider.oneDrive ? 'OneDrive' : '로컬 폴더'} 동기화 설정 완료',
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _disableSync() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('동기화 해제'),
        content: const Text(
          '동기화를 해제하시겠습니까?\n\n로컬 노트는 유지되지만, 클라우드와 더 이상 동기화되지 않습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('해제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _cloudSync.disableSync();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('동기화가 해제되었습니다')),
        );
      }
    }
  }
}
