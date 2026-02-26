import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'note_storage_service.dart';

/// Service for backing up and restoring notes
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  /// Get the backup directory path
  Future<String> getBackupDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${docsDir.path}/Winote/backups');
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir.path;
  }

  /// Create a backup of all notes
  /// Returns the backup file path on success, null on failure
  Future<String?> createBackup() async {
    try {
      final storageService = NoteStorageService.instance;
      final notes = await storageService.listNotes();
      final folders = await storageService.listFolders();

      if (notes.isEmpty && folders.isEmpty) {
        debugPrint('[BackupService] No data to backup');
        return null;
      }

      // Create backup data structure
      final backupData = {
        'version': 1,
        'createdAt': DateTime.now().toIso8601String(),
        'notes': notes.map((n) => n.toJson()).toList(),
        'folders': folders.map((f) => f.toJson()).toList(),
      };

      // Convert to JSON
      final jsonString = const JsonEncoder.withIndent('  ').convert(backupData);
      final jsonBytes = utf8.encode(jsonString);

      // Compress using GZip
      final gzipBytes = GZipEncoder().encode(jsonBytes);
      if (gzipBytes == null) {
        debugPrint('[BackupService] Failed to compress backup');
        return null;
      }

      // Save to file
      final backupDir = await getBackupDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'winote_backup_$timestamp.wbk';
      final filePath = '$backupDir/$fileName';

      final file = File(filePath);
      await file.writeAsBytes(gzipBytes);

      debugPrint('[BackupService] Backup created: $filePath');
      debugPrint('[BackupService] Notes: ${notes.length}, Folders: ${folders.length}');

      return filePath;
    } catch (e) {
      debugPrint('[BackupService] Backup error: $e');
      return null;
    }
  }

  /// Restore notes from a backup file
  /// Returns true on success, false on failure
  Future<BackupRestoreResult> restoreBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return BackupRestoreResult(
          success: false,
          message: '백업 파일을 찾을 수 없습니다',
        );
      }

      // Read and decompress
      final gzipBytes = await file.readAsBytes();
      final jsonBytes = GZipDecoder().decodeBytes(gzipBytes);
      final jsonString = utf8.decode(jsonBytes);
      final backupData = jsonDecode(jsonString) as Map<String, dynamic>;

      // Validate version
      final version = backupData['version'] as int? ?? 0;
      if (version != 1) {
        return BackupRestoreResult(
          success: false,
          message: '지원되지 않는 백업 버전입니다',
        );
      }

      final storageService = NoteStorageService.instance;

      // Restore folders first
      final foldersJson = backupData['folders'] as List<dynamic>? ?? [];
      int restoredFolders = 0;
      for (final folderJson in foldersJson) {
        try {
          final folder = NoteFolder.fromJson(folderJson as Map<String, dynamic>);
          await storageService.createFolderWithId(folder);
          restoredFolders++;
        } catch (e) {
          debugPrint('[BackupService] Failed to restore folder: $e');
        }
      }

      // Restore notes
      final notesJson = backupData['notes'] as List<dynamic>? ?? [];
      int restoredNotes = 0;
      for (final noteJson in notesJson) {
        try {
          final note = Note.fromJson(noteJson as Map<String, dynamic>);
          await storageService.saveNote(note);
          restoredNotes++;
        } catch (e) {
          debugPrint('[BackupService] Failed to restore note: $e');
        }
      }

      final createdAt = backupData['createdAt'] as String?;
      DateTime? backupDate;
      if (createdAt != null) {
        backupDate = DateTime.tryParse(createdAt);
      }

      return BackupRestoreResult(
        success: true,
        message: '복원 완료: 노트 $restoredNotes개, 폴더 $restoredFolders개',
        restoredNotes: restoredNotes,
        restoredFolders: restoredFolders,
        backupDate: backupDate,
      );
    } catch (e) {
      debugPrint('[BackupService] Restore error: $e');
      return BackupRestoreResult(
        success: false,
        message: '복원 실패: $e',
      );
    }
  }

  /// List all available backups
  Future<List<BackupInfo>> listBackups() async {
    try {
      final backupDir = await getBackupDirectory();
      final dir = Directory(backupDir);

      if (!await dir.exists()) {
        return [];
      }

      final files = await dir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.wbk'))
          .cast<File>()
          .toList();

      final backups = <BackupInfo>[];
      for (final file in files) {
        try {
          final stat = await file.stat();
          final fileName = file.path.split(Platform.pathSeparator).last;

          // Try to read backup info
          int noteCount = 0;
          int folderCount = 0;
          DateTime? backupDate;

          try {
            final gzipBytes = await file.readAsBytes();
            final jsonBytes = GZipDecoder().decodeBytes(gzipBytes);
            final jsonString = utf8.decode(jsonBytes);
            final data = jsonDecode(jsonString) as Map<String, dynamic>;

            noteCount = (data['notes'] as List?)?.length ?? 0;
            folderCount = (data['folders'] as List?)?.length ?? 0;
            final createdAt = data['createdAt'] as String?;
            if (createdAt != null) {
              backupDate = DateTime.tryParse(createdAt);
            }
          } catch (_) {
            // Ignore parse errors, use file stats
          }

          backups.add(BackupInfo(
            filePath: file.path,
            fileName: fileName,
            fileSize: stat.size,
            createdAt: backupDate ?? stat.modified,
            noteCount: noteCount,
            folderCount: folderCount,
          ),);
        } catch (e) {
          debugPrint('[BackupService] Error reading backup info: $e');
        }
      }

      // Sort by date, newest first
      backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return backups;
    } catch (e) {
      debugPrint('[BackupService] List backups error: $e');
      return [];
    }
  }

  /// Delete a backup file
  Future<bool> deleteBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[BackupService] Delete backup error: $e');
      return false;
    }
  }

  /// Format file size for display
  String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Export backup to external location (user-selected)
  Future<String?> exportBackupToExternal() async {
    try {
      // First create a backup
      final backupPath = await createBackup();
      if (backupPath == null) {
        return null;
      }

      // Let user choose directory (more reliable on Windows than saveFile)
      final selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '백업 파일 저장 위치 선택',
      );

      if (selectedDirectory == null) {
        return null; // User cancelled
      }

      // Copy backup file to selected directory
      final sourceFile = File(backupPath);
      final fileName = backupPath.split(Platform.pathSeparator).last;
      final destPath = '$selectedDirectory${Platform.pathSeparator}$fileName';
      await sourceFile.copy(destPath);

      debugPrint('[BackupService] Exported backup to: $destPath');
      return destPath;
    } catch (e) {
      debugPrint('[BackupService] Export error: $e');
      return null;
    }
  }

  /// Import backup from external file
  Future<BackupRestoreResult> importBackupFromExternal() async {
    try {
      // Let user select backup file
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '백업 파일 선택',
        type: FileType.custom,
        allowedExtensions: ['wbk'],
      );

      if (result == null || result.files.isEmpty) {
        return BackupRestoreResult(
          success: false,
          message: '파일이 선택되지 않았습니다',
        );
      }

      final filePath = result.files.single.path;
      if (filePath == null) {
        return BackupRestoreResult(
          success: false,
          message: '파일 경로를 가져올 수 없습니다',
        );
      }

      // Restore from selected file
      return await restoreBackup(filePath);
    } catch (e) {
      debugPrint('[BackupService] Import error: $e');
      return BackupRestoreResult(
        success: false,
        message: '가져오기 실패: $e',
      );
    }
  }

  /// Share backup file
  Future<bool> shareBackup(String? filePath) async {
    try {
      String backupPath;

      if (filePath != null) {
        backupPath = filePath;
      } else {
        // Create a new backup if no path provided
        final newBackup = await createBackup();
        if (newBackup == null) {
          return false;
        }
        backupPath = newBackup;
      }

      final file = File(backupPath);
      if (!await file.exists()) {
        return false;
      }

      await Share.shareXFiles(
        [XFile(backupPath)],
        subject: 'Winote 백업',
        text: 'Winote 노트 백업 파일입니다.',
      );

      return true;
    } catch (e) {
      debugPrint('[BackupService] Share error: $e');
      return false;
    }
  }

  /// Export single note as .wnote file
  Future<String?> exportNote(Note note) async {
    try {
      final noteData = {
        'version': 1,
        'type': 'single_note',
        'exportedAt': DateTime.now().toIso8601String(),
        'note': note.toJson(),
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(noteData);
      final jsonBytes = utf8.encode(jsonString);
      final gzipBytes = GZipEncoder().encode(jsonBytes);

      if (gzipBytes == null) {
        return null;
      }

      // Clean filename
      final cleanTitle = note.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = '${cleanTitle}_$timestamp.wnote';

      // Let user choose directory (more reliable on Windows than saveFile)
      final selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '노트 내보내기 위치 선택',
      );

      if (selectedDirectory == null) {
        return null;
      }

      final destPath = '$selectedDirectory${Platform.pathSeparator}$fileName';
      final file = File(destPath);
      await file.writeAsBytes(gzipBytes);

      debugPrint('[BackupService] Exported note to: $destPath');
      return destPath;
    } catch (e) {
      debugPrint('[BackupService] Export note error: $e');
      return null;
    }
  }

  /// Import single note from .wnote file
  Future<Note?> importNote() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '노트 가져오기',
        type: FileType.custom,
        allowedExtensions: ['wnote'],
      );

      if (result == null || result.files.isEmpty) {
        return null;
      }

      final filePath = result.files.single.path;
      if (filePath == null) {
        return null;
      }

      final file = File(filePath);
      final gzipBytes = await file.readAsBytes();
      final jsonBytes = GZipDecoder().decodeBytes(gzipBytes);
      final jsonString = utf8.decode(jsonBytes);
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      // Validate
      if (data['type'] != 'single_note') {
        debugPrint('[BackupService] Invalid note file type');
        return null;
      }

      final noteJson = data['note'] as Map<String, dynamic>;
      final note = Note.fromJson(noteJson);

      // Save to storage with new ID to avoid conflicts
      final storageService = NoteStorageService.instance;
      final newNote = note.copyWith(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: '${note.title} (가져옴)',
      );
      await storageService.saveNote(newNote);

      return newNote;
    } catch (e) {
      debugPrint('[BackupService] Import note error: $e');
      return null;
    }
  }

  /// Share single note
  Future<bool> shareNote(Note note) async {
    try {
      // Create temporary note file
      final noteData = {
        'version': 1,
        'type': 'single_note',
        'exportedAt': DateTime.now().toIso8601String(),
        'note': note.toJson(),
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(noteData);
      final jsonBytes = utf8.encode(jsonString);
      final gzipBytes = GZipEncoder().encode(jsonBytes);

      if (gzipBytes == null) {
        return false;
      }

      // Create temp file
      final tempDir = await getTemporaryDirectory();
      final cleanTitle = note.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final tempPath = '${tempDir.path}/$cleanTitle.wnote';
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(gzipBytes);

      await Share.shareXFiles(
        [XFile(tempPath)],
        subject: note.title,
        text: 'Winote 노트: ${note.title}',
      );

      return true;
    } catch (e) {
      debugPrint('[BackupService] Share note error: $e');
      return false;
    }
  }
}

/// Backup information
class BackupInfo {
  final String filePath;
  final String fileName;
  final int fileSize;
  final DateTime createdAt;
  final int noteCount;
  final int folderCount;

  BackupInfo({
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    required this.createdAt,
    required this.noteCount,
    required this.folderCount,
  });
}

/// Backup restore result
class BackupRestoreResult {
  final bool success;
  final String message;
  final int restoredNotes;
  final int restoredFolders;
  final DateTime? backupDate;

  BackupRestoreResult({
    required this.success,
    required this.message,
    this.restoredNotes = 0,
    this.restoredFolders = 0,
    this.backupDate,
  });
}
