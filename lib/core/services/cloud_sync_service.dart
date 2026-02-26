import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'note_storage_service.dart';

/// 클라우드 동기화 상태
enum SyncStatus {
  idle,       // 대기 중
  syncing,    // 동기화 중
  success,    // 성공
  error,      // 오류
  offline,    // 오프라인
}

/// 파일 변경 이벤트 타입
enum FileChangeType {
  created,
  modified,
  deleted,
}

/// 클라우드 제공자 종류
enum CloudProvider {
  none,       // 동기화 비활성화
  oneDrive,   // Microsoft OneDrive
  local,      // 로컬 폴더 (테스트/백업용)
}

/// 동기화 이벤트 리스너
typedef SyncStatusListener = void Function(SyncStatus status, String? message);

/// 파일 변경 이벤트 리스너
typedef FileChangeListener = void Function(String noteId, FileChangeType type);

/// 클라우드 동기화 서비스
/// OneDrive 또는 로컬 폴더로 노트를 동기화합니다.
class CloudSyncService {
  static CloudSyncService? _instance;
  static CloudSyncService get instance {
    _instance ??= CloudSyncService._();
    return _instance!;
  }

  CloudSyncService._();

  // 상태
  SyncStatus _status = SyncStatus.idle;
  CloudProvider _provider = CloudProvider.none;
  String? _syncPath; // 동기화 대상 폴더 경로
  DateTime? _lastSyncTime;
  final List<SyncStatusListener> _listeners = [];

  // 실시간 동기화 관련
  bool _realtimeSyncEnabled = false;
  bool _fileWatchEnabled = false;
  StreamSubscription<FileSystemEvent>? _fileWatcher;
  final List<FileChangeListener> _fileChangeListeners = [];
  Timer? _debounceTimer;
  final Set<String> _pendingChanges = {}; // 처리 대기 중인 파일 변경

  // Getters
  SyncStatus get status => _status;
  CloudProvider get provider => _provider;
  String? get syncPath => _syncPath;
  DateTime? get lastSyncTime => _lastSyncTime;
  bool get isEnabled => _provider != CloudProvider.none && _syncPath != null;
  bool get isRealtimeSyncEnabled => _realtimeSyncEnabled;
  bool get isFileWatchEnabled => _fileWatchEnabled;

  /// 상태 변경 리스너 등록
  void addStatusListener(SyncStatusListener listener) {
    _listeners.add(listener);
  }

  /// 상태 변경 리스너 제거
  void removeStatusListener(SyncStatusListener listener) {
    _listeners.remove(listener);
  }

  /// 파일 변경 리스너 등록
  void addFileChangeListener(FileChangeListener listener) {
    _fileChangeListeners.add(listener);
  }

  /// 파일 변경 리스너 제거
  void removeFileChangeListener(FileChangeListener listener) {
    _fileChangeListeners.remove(listener);
  }

  /// 파일 변경 알림
  void _notifyFileChange(String noteId, FileChangeType type) {
    for (final listener in _fileChangeListeners) {
      listener(noteId, type);
    }
  }

  /// 상태 변경 알림
  void _notifyStatus(SyncStatus status, [String? message]) {
    _status = status;
    for (final listener in _listeners) {
      listener(status, message);
    }
  }

  /// 동기화 설정 초기화
  Future<void> initialize() async {
    final appDir = await getApplicationDocumentsDirectory();
    final configPath = '${appDir.path}${Platform.pathSeparator}Winote${Platform.pathSeparator}sync_config.json';

    final configFile = File(configPath);
    if (await configFile.exists()) {
      try {
        final jsonString = await configFile.readAsString();
        final config = jsonDecode(jsonString) as Map<String, dynamic>;

        _provider = CloudProvider.values[config['provider'] as int? ?? 0];
        _syncPath = config['syncPath'] as String?;
        _lastSyncTime = config['lastSyncTime'] != null
            ? DateTime.parse(config['lastSyncTime'] as String)
            : null;
        _realtimeSyncEnabled = config['realtimeSync'] as bool? ?? false;
        _fileWatchEnabled = config['fileWatch'] as bool? ?? false;

        debugPrint('[CloudSync] Loaded config: provider=$_provider, path=$_syncPath, realtime=$_realtimeSyncEnabled, watch=$_fileWatchEnabled');

        // 파일 감시가 활성화되어 있으면 시작
        if (_fileWatchEnabled && _syncPath != null) {
          _startFileWatcher();
        }
      } catch (e) {
        debugPrint('[CloudSync] Error loading config: $e');
      }
    }
  }

  /// 설정 저장
  Future<void> _saveConfig() async {
    final appDir = await getApplicationDocumentsDirectory();
    final configPath = '${appDir.path}${Platform.pathSeparator}Winote${Platform.pathSeparator}sync_config.json';

    final configFile = File(configPath);
    final dir = configFile.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final config = {
      'provider': _provider.index,
      'syncPath': _syncPath,
      'lastSyncTime': _lastSyncTime?.toIso8601String(),
      'realtimeSync': _realtimeSyncEnabled,
      'fileWatch': _fileWatchEnabled,
    };

    await configFile.writeAsString(jsonEncode(config));
  }

  /// 동기화 폴더 설정 (OneDrive 또는 로컬)
  Future<bool> setSyncFolder(String path, CloudProvider provider) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
      } catch (e) {
        debugPrint('[CloudSync] Failed to create sync folder: $e');
        return false;
      }
    }

    // Winote 하위 폴더 생성
    final winoteDir = Directory('$path${Platform.pathSeparator}Winote');
    if (!await winoteDir.exists()) {
      await winoteDir.create(recursive: true);
    }

    _provider = provider;
    _syncPath = winoteDir.path;
    await _saveConfig();

    debugPrint('[CloudSync] Sync folder set: $_syncPath (provider: $provider)');
    return true;
  }

  /// 동기화 비활성화
  Future<void> disableSync() async {
    _stopFileWatcher();
    _provider = CloudProvider.none;
    _syncPath = null;
    _realtimeSyncEnabled = false;
    _fileWatchEnabled = false;
    await _saveConfig();
    _notifyStatus(SyncStatus.idle, '동기화 비활성화됨');
  }

  /// 실시간 동기화 설정 (노트 저장 시 즉시 업로드)
  Future<void> setRealtimeSync(bool enabled) async {
    _realtimeSyncEnabled = enabled;
    await _saveConfig();
    debugPrint('[CloudSync] Realtime sync: $enabled');
  }

  /// 파일 감시 설정 (OneDrive 폴더 변경 감지)
  Future<void> setFileWatch(bool enabled) async {
    _fileWatchEnabled = enabled;
    if (enabled && _syncPath != null) {
      _startFileWatcher();
    } else {
      _stopFileWatcher();
    }
    await _saveConfig();
    debugPrint('[CloudSync] File watch: $enabled');
  }

  /// 파일 감시 시작
  void _startFileWatcher() {
    _stopFileWatcher(); // 기존 감시 중지

    if (_syncPath == null) return;

    final syncDir = Directory(_syncPath!);
    if (!syncDir.existsSync()) return;

    debugPrint('[CloudSync] Starting file watcher on: $_syncPath');

    _fileWatcher = syncDir.watch(events: FileSystemEvent.all).listen(
      (event) {
        // .winote 파일만 처리
        if (!event.path.endsWith('.winote')) return;

        final fileName = event.path.split(Platform.pathSeparator).last;
        final noteId = fileName.replaceAll('.winote', '');

        debugPrint('[CloudSync] File event: ${event.type} - $fileName');

        // 디바운스: 짧은 시간 내 여러 이벤트를 하나로 묶음
        _pendingChanges.add(noteId);
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 500), () {
          _processPendingChanges();
        });
      },
      onError: (error) {
        debugPrint('[CloudSync] File watcher error: $error');
      },
    );
  }

  /// 파일 감시 중지
  void _stopFileWatcher() {
    _fileWatcher?.cancel();
    _fileWatcher = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingChanges.clear();
    debugPrint('[CloudSync] File watcher stopped');
  }

  /// 대기 중인 파일 변경 처리
  Future<void> _processPendingChanges() async {
    if (_pendingChanges.isEmpty) return;

    final changes = Set<String>.from(_pendingChanges);
    _pendingChanges.clear();

    debugPrint('[CloudSync] Processing ${changes.length} pending changes');

    for (final noteId in changes) {
      final filePath = '$_syncPath${Platform.pathSeparator}$noteId.winote';
      final file = File(filePath);

      if (await file.exists()) {
        // 파일이 존재하면 다운로드 (생성 또는 수정)
        try {
          final jsonString = await file.readAsString();
          final remoteNote = Note.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);

          // 로컬 노트와 비교
          final storageService = NoteStorageService.instance;
          final localNote = await storageService.loadNote(noteId);

          if (localNote == null || remoteNote.modifiedAt.isAfter(localNote.modifiedAt)) {
            // 원격이 더 최신이면 다운로드
            await storageService.saveNote(remoteNote);
            _notifyFileChange(noteId, FileChangeType.modified);
            debugPrint('[CloudSync] Downloaded: ${remoteNote.title}');
          }
        } catch (e) {
          debugPrint('[CloudSync] Error processing change for $noteId: $e');
        }
      } else {
        // 파일이 삭제됨
        _notifyFileChange(noteId, FileChangeType.deleted);
        debugPrint('[CloudSync] Remote file deleted: $noteId');
      }
    }
  }

  /// 노트 즉시 업로드 (실시간 동기화용)
  Future<bool> uploadNoteImmediately(Note note) async {
    if (!isEnabled || !_realtimeSyncEnabled) return false;

    try {
      _notifyStatus(SyncStatus.syncing, '업로드 중...');
      await _uploadNote(note);
      _lastSyncTime = DateTime.now();
      await _saveConfig();
      _notifyStatus(SyncStatus.success, '업로드 완료: ${note.title}');
      return true;
    } catch (e) {
      debugPrint('[CloudSync] Immediate upload error: $e');
      _notifyStatus(SyncStatus.error, '업로드 실패: $e');
      return false;
    }
  }

  /// 서비스 정리 (앱 종료 시)
  void dispose() {
    _stopFileWatcher();
    _listeners.clear();
    _fileChangeListeners.clear();
  }

  /// 전체 동기화 수행
  Future<SyncResult> syncAll() async {
    if (!isEnabled) {
      return SyncResult(
        success: false,
        message: '동기화가 설정되지 않았습니다',
        uploaded: 0,
        downloaded: 0,
      );
    }

    _notifyStatus(SyncStatus.syncing, '동기화 중...');

    try {
      final storageService = NoteStorageService.instance;
      final localNotes = await storageService.listNotes();
      final remoteNotes = await _listRemoteNotes();

      int uploaded = 0;
      int downloaded = 0;

      // 1. 로컬 노트를 클라우드로 업로드 (신규 또는 로컬이 더 최신인 경우)
      for (final localNote in localNotes) {
        final remoteNote = remoteNotes.firstWhere(
          (n) => n.id == localNote.id,
          orElse: () => localNote.copyWith(modifiedAt: DateTime.fromMillisecondsSinceEpoch(0)),
        );

        if (localNote.modifiedAt.isAfter(remoteNote.modifiedAt)) {
          await _uploadNote(localNote);
          uploaded++;
        }
      }

      // 2. 클라우드 노트를 로컬로 다운로드 (신규 또는 클라우드가 더 최신인 경우)
      for (final remoteNote in remoteNotes) {
        final localNote = localNotes.firstWhere(
          (n) => n.id == remoteNote.id,
          orElse: () => remoteNote.copyWith(modifiedAt: DateTime.fromMillisecondsSinceEpoch(0)),
        );

        if (remoteNote.modifiedAt.isAfter(localNote.modifiedAt)) {
          await storageService.saveNote(remoteNote);
          downloaded++;
        }
      }

      _lastSyncTime = DateTime.now();
      await _saveConfig();

      final message = '동기화 완료: $uploaded개 업로드, $downloaded개 다운로드';
      _notifyStatus(SyncStatus.success, message);

      return SyncResult(
        success: true,
        message: message,
        uploaded: uploaded,
        downloaded: downloaded,
      );
    } catch (e) {
      final message = '동기화 오류: $e';
      _notifyStatus(SyncStatus.error, message);
      return SyncResult(
        success: false,
        message: message,
        uploaded: 0,
        downloaded: 0,
      );
    }
  }

  /// 단일 노트 업로드
  Future<bool> uploadNote(Note note) async {
    if (!isEnabled) return false;

    try {
      await _uploadNote(note);
      return true;
    } catch (e) {
      debugPrint('[CloudSync] Upload error: $e');
      return false;
    }
  }

  /// 원격 노트 목록 조회
  Future<List<Note>> _listRemoteNotes() async {
    if (_syncPath == null) return [];

    final syncDir = Directory(_syncPath!);
    if (!await syncDir.exists()) return [];

    final notes = <Note>[];

    await for (final entity in syncDir.list()) {
      if (entity is File && entity.path.endsWith('.winote')) {
        try {
          final jsonString = await entity.readAsString();
          final note = Note.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
          notes.add(note);
        } catch (e) {
          debugPrint('[CloudSync] Error reading remote note: $e');
        }
      }
    }

    return notes;
  }

  /// 노트를 클라우드 폴더에 저장
  Future<void> _uploadNote(Note note) async {
    if (_syncPath == null) return;

    final filePath = '$_syncPath${Platform.pathSeparator}${note.id}.winote';
    final file = File(filePath);

    final jsonString = jsonEncode(note.toJson());
    await file.writeAsString(jsonString);

    debugPrint('[CloudSync] Uploaded: ${note.title}');
  }

  /// OneDrive 경로 감지 (Windows)
  Future<String?> detectOneDrivePath() async {
    if (!Platform.isWindows) return null;

    // 일반적인 OneDrive 경로들
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile == null) return null;

    final possiblePaths = [
      '$userProfile\\OneDrive',
      '$userProfile\\OneDrive - Personal',
      '$userProfile\\OneDrive - 개인',
    ];

    for (final path in possiblePaths) {
      final dir = Directory(path);
      if (await dir.exists()) {
        debugPrint('[CloudSync] Found OneDrive: $path');
        return path;
      }
    }

    return null;
  }

  /// 동기화 상태 문자열
  String getStatusText() {
    switch (_status) {
      case SyncStatus.idle:
        if (_lastSyncTime != null) {
          return '마지막 동기화: ${_formatTime(_lastSyncTime!)}';
        }
        return '동기화 대기 중';
      case SyncStatus.syncing:
        return '동기화 중...';
      case SyncStatus.success:
        return '동기화 완료';
      case SyncStatus.error:
        return '동기화 오류';
      case SyncStatus.offline:
        return '오프라인';
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inDays < 1) return '${diff.inHours}시간 전';
    return '${time.month}/${time.day} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }
}

/// 동기화 결과
class SyncResult {
  final bool success;
  final String message;
  final int uploaded;
  final int downloaded;

  SyncResult({
    required this.success,
    required this.message,
    required this.uploaded,
    required this.downloaded,
  });
}
