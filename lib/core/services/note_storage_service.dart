import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/stroke.dart';
import '../../domain/entities/stroke_point.dart';

/// Page model for multi-page notes
class NotePage {
  final int pageNumber;
  final List<Stroke> strokes;

  NotePage({
    required this.pageNumber,
    required this.strokes,
  });

  Map<String, dynamic> toJson() {
    return {
      'pageNumber': pageNumber,
      'strokes': strokes.map((s) => _strokeToJson(s)).toList(),
    };
  }

  factory NotePage.fromJson(Map<String, dynamic> json) {
    return NotePage(
      pageNumber: json['pageNumber'] as int,
      strokes: (json['strokes'] as List)
          .map((s) => _strokeFromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  NotePage copyWith({
    int? pageNumber,
    List<Stroke>? strokes,
  }) {
    return NotePage(
      pageNumber: pageNumber ?? this.pageNumber,
      strokes: strokes ?? List.from(this.strokes),
    );
  }

  static Map<String, dynamic> _strokeToJson(Stroke stroke) {
    return {
      'id': stroke.id,
      'toolType': stroke.toolType.index,
      'color': stroke.color.value,
      'width': stroke.width,
      'points': stroke.points.map((p) => {
        'x': p.x,
        'y': p.y,
        'pressure': p.pressure,
        'tilt': p.tilt,
        'timestamp': p.timestamp,
      }).toList(),
      'timestamp': stroke.timestamp,
    };
  }

  static Stroke _strokeFromJson(Map<String, dynamic> json) {
    return Stroke(
      id: json['id'] as String,
      toolType: ToolType.values[json['toolType'] as int],
      color: Color(json['color'] as int),
      width: (json['width'] as num).toDouble(),
      points: (json['points'] as List).map((p) {
        final point = p as Map<String, dynamic>;
        return StrokePoint(
          x: (point['x'] as num).toDouble(),
          y: (point['y'] as num).toDouble(),
          pressure: (point['pressure'] as num).toDouble(),
          tilt: (point['tilt'] as num?)?.toDouble() ?? 0.0,
          timestamp: point['timestamp'] as int,
        );
      }).toList(),
      timestamp: json['timestamp'] as int,
    );
  }
}

/// Note model for storage with multi-page support
class Note {
  final String id;
  final String title;
  final List<NotePage> pages;
  final DateTime createdAt;
  final DateTime modifiedAt;

  Note({
    required this.id,
    required this.title,
    required this.pages,
    required this.createdAt,
    required this.modifiedAt,
  });

  /// Get all strokes across all pages (for backward compatibility)
  List<Stroke> get strokes {
    final allStrokes = <Stroke>[];
    for (final page in pages) {
      allStrokes.addAll(page.strokes);
    }
    return allStrokes;
  }

  /// Get strokes for a specific page
  List<Stroke> getStrokesForPage(int pageNumber) {
    final page = pages.firstWhere(
      (p) => p.pageNumber == pageNumber,
      orElse: () => NotePage(pageNumber: pageNumber, strokes: []),
    );
    return page.strokes;
  }

  /// Get page count
  int get pageCount => pages.isEmpty ? 1 : pages.length;

  /// Legacy JSON format support (single page)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'pages': pages.map((p) => p.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt.toIso8601String(),
      'version': 2, // New multi-page format
    };
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    // Check version for backward compatibility
    final version = json['version'] as int? ?? 1;

    if (version >= 2 && json.containsKey('pages')) {
      // New multi-page format
      return Note(
        id: json['id'] as String,
        title: json['title'] as String,
        pages: (json['pages'] as List)
            .map((p) => NotePage.fromJson(p as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      );
    } else {
      // Legacy single-page format
      final strokes = json.containsKey('strokes')
          ? (json['strokes'] as List)
              .map((s) => NotePage._strokeFromJson(s as Map<String, dynamic>))
              .toList()
          : <Stroke>[];

      return Note(
        id: json['id'] as String,
        title: json['title'] as String,
        pages: [NotePage(pageNumber: 0, strokes: strokes)],
        createdAt: DateTime.parse(json['createdAt'] as String),
        modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      );
    }
  }

  Note copyWith({
    String? id,
    String? title,
    List<NotePage>? pages,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      pages: pages ?? this.pages.map((p) => p.copyWith()).toList(),
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
  }

  /// Update strokes for a specific page
  Note updatePageStrokes(int pageNumber, List<Stroke> strokes) {
    final newPages = <NotePage>[];
    bool pageFound = false;

    for (final page in pages) {
      if (page.pageNumber == pageNumber) {
        newPages.add(page.copyWith(strokes: strokes));
        pageFound = true;
      } else {
        newPages.add(page);
      }
    }

    if (!pageFound) {
      newPages.add(NotePage(pageNumber: pageNumber, strokes: strokes));
      newPages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    }

    return copyWith(
      pages: newPages,
      modifiedAt: DateTime.now(),
    );
  }

  /// Add a new page
  Note addPage() {
    final maxPageNumber = pages.isEmpty
        ? -1
        : pages.map((p) => p.pageNumber).reduce((a, b) => a > b ? a : b);
    final newPage = NotePage(pageNumber: maxPageNumber + 1, strokes: []);

    return copyWith(
      pages: [...pages, newPage],
      modifiedAt: DateTime.now(),
    );
  }

  /// Delete a page
  Note deletePage(int pageNumber) {
    if (pages.length <= 1) return this;

    final newPages = pages.where((p) => p.pageNumber != pageNumber).toList();

    return copyWith(
      pages: newPages,
      modifiedAt: DateTime.now(),
    );
  }
}

/// Service for saving and loading notes
class NoteStorageService {
  static NoteStorageService? _instance;
  static NoteStorageService get instance {
    _instance ??= NoteStorageService._();
    return _instance!;
  }

  NoteStorageService._();

  String? _notesDirectory;

  /// Get the notes directory
  Future<String> get notesDirectory async {
    if (_notesDirectory != null) return _notesDirectory!;

    final appDir = await getApplicationDocumentsDirectory();
    _notesDirectory = '${appDir.path}${Platform.pathSeparator}Winote${Platform.pathSeparator}notes';

    // Create directory if it doesn't exist
    final dir = Directory(_notesDirectory!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return _notesDirectory!;
  }

  /// Save a note to file
  Future<void> saveNote(Note note) async {
    final dir = await notesDirectory;
    final file = File('$dir${Platform.pathSeparator}${note.id}.json');

    final jsonString = jsonEncode(note.toJson());
    await file.writeAsString(jsonString);

    debugPrint('[NoteStorageService] Note saved: ${note.id}');
  }

  /// Load a note from file
  Future<Note?> loadNote(String noteId) async {
    try {
      final dir = await notesDirectory;
      final file = File('$dir${Platform.pathSeparator}$noteId.json');

      if (!await file.exists()) {
        debugPrint('[NoteStorageService] Note not found: $noteId');
        return null;
      }

      final jsonString = await file.readAsString();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final note = Note.fromJson(json);

      debugPrint('[NoteStorageService] Note loaded: $noteId (${note.strokes.length} strokes)');
      return note;
    } catch (e) {
      debugPrint('[NoteStorageService] Error loading note $noteId: $e');
      return null;
    }
  }

  /// Delete a note
  Future<bool> deleteNote(String noteId) async {
    try {
      final dir = await notesDirectory;
      final file = File('$dir${Platform.pathSeparator}$noteId.json');

      if (await file.exists()) {
        await file.delete();
        debugPrint('[NoteStorageService] Note deleted: $noteId');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[NoteStorageService] Error deleting note $noteId: $e');
      return false;
    }
  }

  /// List all notes (metadata only for performance)
  Future<List<Note>> listNotes() async {
    try {
      final dir = await notesDirectory;
      final directory = Directory(dir);

      if (!await directory.exists()) {
        return [];
      }

      final notes = <Note>[];
      await for (final entity in directory.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            final jsonString = await entity.readAsString();
            final json = jsonDecode(jsonString) as Map<String, dynamic>;
            notes.add(Note.fromJson(json));
          } catch (e) {
            debugPrint('[NoteStorageService] Error reading ${entity.path}: $e');
          }
        }
      }

      // Sort by modified date (newest first)
      notes.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));

      debugPrint('[NoteStorageService] Listed ${notes.length} notes');
      return notes;
    } catch (e) {
      debugPrint('[NoteStorageService] Error listing notes: $e');
      return [];
    }
  }

  /// Create a new note
  Note createNewNote({String? title}) {
    final now = DateTime.now();
    final id = now.millisecondsSinceEpoch.toString();

    return Note(
      id: id,
      title: title ?? '새 노트 ${now.month}/${now.day} ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
      pages: [NotePage(pageNumber: 0, strokes: [])],
      createdAt: now,
      modifiedAt: now,
    );
  }

  /// Update note with strokes (backward compatible - updates page 0)
  Note updateNoteStrokes(Note note, List<Stroke> strokes) {
    return note.updatePageStrokes(0, strokes);
  }
}
