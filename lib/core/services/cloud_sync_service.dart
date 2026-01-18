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

/// 클라우드 제공자 종류
enum CloudProvider {
  none,       // 동기화 비활성화
  oneDrive,   // Microsoft OneDrive
  local,      // 로컬 폴더 (테스트/백업용)
}

/// 동기화 이벤트 리스너
typedef SyncStatusListener = void Function(SyncStatus status, String? message);

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

  // Getters
  SyncStatus get status => _status;
  CloudProvider get provider => _provider;
  String? get syncPath => _syncPath;
  DateTime? get lastSyncTime => _lastSyncTime;
  bool get isEnabled => _provider != CloudProvider.none && _syncPath != null;

  /// 상태 변경 리스너 등록
  void addStatusListener(SyncStatusListener listener) {
    _listeners.add(listener);
  }

  /// 상태 변경 리스너 제거
  void removeStatusListener(SyncStatusListener listener) {
    _listeners.remove(listener);
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

        debugPrint('[CloudSync] Loaded config: provider=$_provider, path=$_syncPath');
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
    _provider = CloudProvider.none;
    _syncPath = null;
    await _saveConfig();
    _notifyStatus(SyncStatus.idle, '동기화 비활성화됨');
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
