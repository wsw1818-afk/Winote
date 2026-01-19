import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/stroke.dart';
import '../../domain/entities/stroke_point.dart';
import '../../domain/entities/canvas_shape.dart';

/// Page model for multi-page notes
class NotePage {
  final int pageNumber;
  final List<Stroke> strokes;
  final List<CanvasShape> shapes;
  final String? backgroundImagePath; // 커스텀 배경 이미지 경로 (Canva 등에서 가져온 이미지)
  final int? templateIndex; // PageTemplate enum index (저장용)
  final int? overlayTemplateIndex; // 배경 이미지 위에 표시할 템플릿 (lined, grid, dotted 등)

  NotePage({
    required this.pageNumber,
    required this.strokes,
    this.shapes = const [],
    this.backgroundImagePath,
    this.templateIndex,
    this.overlayTemplateIndex,
  });

  Map<String, dynamic> toJson() {
    return {
      'pageNumber': pageNumber,
      'strokes': strokes.map((s) => _strokeToJson(s)).toList(),
      'shapes': shapes.map((s) => s.toJson()).toList(),
      if (backgroundImagePath != null) 'backgroundImagePath': backgroundImagePath,
      if (templateIndex != null) 'templateIndex': templateIndex,
      if (overlayTemplateIndex != null) 'overlayTemplateIndex': overlayTemplateIndex,
    };
  }

  factory NotePage.fromJson(Map<String, dynamic> json) {
    return NotePage(
      pageNumber: json['pageNumber'] as int,
      strokes: (json['strokes'] as List)
          .map((s) => _strokeFromJson(s as Map<String, dynamic>))
          .toList(),
      shapes: json['shapes'] != null
          ? (json['shapes'] as List)
              .map((s) => CanvasShape.fromJson(s as Map<String, dynamic>))
              .toList()
          : [],
      backgroundImagePath: json['backgroundImagePath'] as String?,
      templateIndex: json['templateIndex'] as int?,
      overlayTemplateIndex: json['overlayTemplateIndex'] as int?,
    );
  }

  NotePage copyWith({
    int? pageNumber,
    List<Stroke>? strokes,
    List<CanvasShape>? shapes,
    String? backgroundImagePath,
    bool clearBackgroundImage = false,
    int? templateIndex,
    bool clearTemplateIndex = false,
    int? overlayTemplateIndex,
    bool clearOverlayTemplateIndex = false,
  }) {
    return NotePage(
      pageNumber: pageNumber ?? this.pageNumber,
      strokes: strokes ?? List.from(this.strokes),
      shapes: shapes ?? List.from(this.shapes),
      backgroundImagePath: clearBackgroundImage ? null : (backgroundImagePath ?? this.backgroundImagePath),
      templateIndex: clearTemplateIndex ? null : (templateIndex ?? this.templateIndex),
      overlayTemplateIndex: clearOverlayTemplateIndex ? null : (overlayTemplateIndex ?? this.overlayTemplateIndex),
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
      'isShape': stroke.isShape,
      'shapeType': stroke.shapeType.index,
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
      isShape: json['isShape'] as bool? ?? false,
      shapeType: json['shapeType'] != null
          ? ShapeType.values[json['shapeType'] as int]
          : ShapeType.none,
    );
  }
}

/// Note model for storage with multi-page support
class Note {
  final String id;
  final String title;
  final String? folderId; // Folder for organizing notes (null = root)
  final List<NotePage> pages;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final bool isFavorite; // 즐겨찾기 여부
  final List<String> tags; // 태그 목록

  Note({
    required this.id,
    required this.title,
    this.folderId,
    required this.pages,
    required this.createdAt,
    required this.modifiedAt,
    this.isFavorite = false,
    this.tags = const [],
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

  /// Get shapes for a specific page
  List<CanvasShape> getShapesForPage(int pageNumber) {
    final page = pages.firstWhere(
      (p) => p.pageNumber == pageNumber,
      orElse: () => NotePage(pageNumber: pageNumber, strokes: []),
    );
    return page.shapes;
  }

  /// Get page count
  int get pageCount => pages.isEmpty ? 1 : pages.length;

  /// Legacy JSON format support (single page)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'folderId': folderId,
      'pages': pages.map((p) => p.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt.toIso8601String(),
      'isFavorite': isFavorite,
      'tags': tags,
      'version': 2, // New multi-page format
    };
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    // Check version for backward compatibility
    final version = json['version'] as int? ?? 1;

    // Parse tags
    final tags = json.containsKey('tags')
        ? (json['tags'] as List).map((t) => t as String).toList()
        : <String>[];

    if (version >= 2 && json.containsKey('pages')) {
      // New multi-page format
      return Note(
        id: json['id'] as String,
        title: json['title'] as String,
        folderId: json['folderId'] as String?,
        pages: (json['pages'] as List)
            .map((p) => NotePage.fromJson(p as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        modifiedAt: DateTime.parse(json['modifiedAt'] as String),
        isFavorite: json['isFavorite'] as bool? ?? false,
        tags: tags,
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
        folderId: json['folderId'] as String?,
        pages: [NotePage(pageNumber: 0, strokes: strokes)],
        createdAt: DateTime.parse(json['createdAt'] as String),
        modifiedAt: DateTime.parse(json['modifiedAt'] as String),
        isFavorite: json['isFavorite'] as bool? ?? false,
        tags: tags,
      );
    }
  }

  Note copyWith({
    String? id,
    String? title,
    String? folderId,
    bool clearFolder = false,
    List<NotePage>? pages,
    DateTime? createdAt,
    DateTime? modifiedAt,
    bool? isFavorite,
    List<String>? tags,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      folderId: clearFolder ? null : (folderId ?? this.folderId),
      pages: pages ?? this.pages.map((p) => p.copyWith()).toList(),
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      tags: tags ?? List.from(this.tags),
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

  /// Update shapes for a specific page
  Note updatePageShapes(int pageNumber, List<CanvasShape> shapes) {
    final newPages = <NotePage>[];
    bool pageFound = false;

    for (final page in pages) {
      if (page.pageNumber == pageNumber) {
        newPages.add(page.copyWith(shapes: shapes));
        pageFound = true;
      } else {
        newPages.add(page);
      }
    }

    if (!pageFound) {
      newPages.add(NotePage(pageNumber: pageNumber, strokes: [], shapes: shapes));
      newPages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    }

    return copyWith(
      pages: newPages,
      modifiedAt: DateTime.now(),
    );
  }

  /// Update background image and overlay template for a specific page
  Note updatePageBackground(int pageNumber, {
    String? backgroundImagePath,
    bool clearBackgroundImage = false,
    int? overlayTemplateIndex,
    bool clearOverlayTemplateIndex = false,
    int? templateIndex,
    bool clearTemplateIndex = false,
  }) {
    final newPages = <NotePage>[];
    bool pageFound = false;

    for (final page in pages) {
      if (page.pageNumber == pageNumber) {
        newPages.add(page.copyWith(
          backgroundImagePath: backgroundImagePath,
          clearBackgroundImage: clearBackgroundImage,
          overlayTemplateIndex: overlayTemplateIndex,
          clearOverlayTemplateIndex: clearOverlayTemplateIndex,
          templateIndex: templateIndex,
          clearTemplateIndex: clearTemplateIndex,
        ));
        pageFound = true;
      } else {
        newPages.add(page);
      }
    }

    if (!pageFound) {
      newPages.add(NotePage(
        pageNumber: pageNumber,
        strokes: [],
        backgroundImagePath: backgroundImagePath,
        overlayTemplateIndex: overlayTemplateIndex,
        templateIndex: templateIndex,
      ));
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

/// Folder model for organizing notes
class NoteFolder {
  final String id;
  final String name;
  final int colorValue; // Folder color for visual identification
  final DateTime createdAt;

  NoteFolder({
    required this.id,
    required this.name,
    this.colorValue = 0xFF2196F3, // Default blue
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'colorValue': colorValue,
    'createdAt': createdAt.toIso8601String(),
  };

  factory NoteFolder.fromJson(Map<String, dynamic> json) => NoteFolder(
    id: json['id'] as String,
    name: json['name'] as String,
    colorValue: json['colorValue'] as int? ?? 0xFF2196F3,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  NoteFolder copyWith({
    String? id,
    String? name,
    int? colorValue,
  }) => NoteFolder(
    id: id ?? this.id,
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
    createdAt: createdAt,
  );
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

  // ===== Folder Management =====

  String? _foldersFilePath;

  Future<String> get _foldersPath async {
    if (_foldersFilePath != null) return _foldersFilePath!;
    final dir = await notesDirectory;
    _foldersFilePath = '$dir${Platform.pathSeparator}..${Platform.pathSeparator}folders.json';
    return _foldersFilePath!;
  }

  /// List all folders
  Future<List<NoteFolder>> listFolders() async {
    try {
      final path = await _foldersPath;
      final file = File(path);

      if (!await file.exists()) {
        return [];
      }

      final jsonString = await file.readAsString();
      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList
          .map((j) => NoteFolder.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[NoteStorageService] Error listing folders: $e');
      return [];
    }
  }

  /// Save folders list
  Future<void> _saveFolders(List<NoteFolder> folders) async {
    try {
      final path = await _foldersPath;
      final file = File(path);
      final jsonString = jsonEncode(folders.map((f) => f.toJson()).toList());
      await file.writeAsString(jsonString);
    } catch (e) {
      debugPrint('[NoteStorageService] Error saving folders: $e');
    }
  }

  /// Create a new folder
  Future<NoteFolder> createFolder(String name, {int? colorValue}) async {
    final folders = await listFolders();
    final folder = NoteFolder(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      colorValue: colorValue ?? 0xFF2196F3,
      createdAt: DateTime.now(),
    );
    folders.add(folder);
    await _saveFolders(folders);
    return folder;
  }

  /// Create a folder with existing ID (for restore)
  Future<void> createFolderWithId(NoteFolder folder) async {
    final folders = await listFolders();
    // Check if folder already exists
    final existingIndex = folders.indexWhere((f) => f.id == folder.id);
    if (existingIndex >= 0) {
      folders[existingIndex] = folder;
    } else {
      folders.add(folder);
    }
    await _saveFolders(folders);
  }

  /// Update a folder
  Future<void> updateFolder(NoteFolder folder) async {
    final folders = await listFolders();
    final index = folders.indexWhere((f) => f.id == folder.id);
    if (index >= 0) {
      folders[index] = folder;
      await _saveFolders(folders);
    }
  }

  /// Delete a folder (notes in folder move to root)
  Future<void> deleteFolder(String folderId) async {
    // Move notes to root
    final notes = await listNotes();
    for (final note in notes.where((n) => n.folderId == folderId)) {
      await saveNote(note.copyWith(clearFolder: true));
    }

    // Remove folder
    final folders = await listFolders();
    folders.removeWhere((f) => f.id == folderId);
    await _saveFolders(folders);
  }

  /// Get notes in a specific folder (null = root folder)
  Future<List<Note>> listNotesInFolder(String? folderId) async {
    final notes = await listNotes();
    return notes.where((n) => n.folderId == folderId).toList();
  }

  /// Move note to folder
  Future<void> moveNoteToFolder(String noteId, String? folderId) async {
    final note = await loadNote(noteId);
    if (note != null) {
      await saveNote(note.copyWith(
        folderId: folderId,
        clearFolder: folderId == null,
        modifiedAt: DateTime.now(),
      ));
    }
  }

  /// Search notes by title
  Future<List<Note>> searchNotes(String query) async {
    if (query.isEmpty) {
      return listNotes();
    }

    final notes = await listNotes();
    final lowerQuery = query.toLowerCase();

    return notes.where((note) {
      // Search in title
      if (note.title.toLowerCase().contains(lowerQuery)) {
        return true;
      }
      return false;
    }).toList();
  }

  // ===== Favorites Management =====

  /// Toggle favorite status of a note
  Future<Note?> toggleFavorite(String noteId) async {
    final note = await loadNote(noteId);
    if (note != null) {
      final updatedNote = note.copyWith(
        isFavorite: !note.isFavorite,
        modifiedAt: DateTime.now(),
      );
      await saveNote(updatedNote);
      debugPrint('[NoteStorageService] Note ${note.isFavorite ? "unfavorited" : "favorited"}: $noteId');
      return updatedNote;
    }
    return null;
  }

  /// Get all favorite notes
  Future<List<Note>> listFavoriteNotes() async {
    final notes = await listNotes();
    return notes.where((note) => note.isFavorite).toList();
  }

  // ===== Tag Management =====

  /// Add a tag to a note
  Future<Note?> addTag(String noteId, String tag) async {
    final note = await loadNote(noteId);
    if (note != null) {
      final normalizedTag = tag.trim().toLowerCase();
      if (normalizedTag.isEmpty || note.tags.contains(normalizedTag)) {
        return note;
      }
      final updatedNote = note.copyWith(
        tags: [...note.tags, normalizedTag],
        modifiedAt: DateTime.now(),
      );
      await saveNote(updatedNote);
      debugPrint('[NoteStorageService] Tag added to note: $normalizedTag');
      return updatedNote;
    }
    return null;
  }

  /// Remove a tag from a note
  Future<Note?> removeTag(String noteId, String tag) async {
    final note = await loadNote(noteId);
    if (note != null) {
      final normalizedTag = tag.trim().toLowerCase();
      final updatedNote = note.copyWith(
        tags: note.tags.where((t) => t != normalizedTag).toList(),
        modifiedAt: DateTime.now(),
      );
      await saveNote(updatedNote);
      debugPrint('[NoteStorageService] Tag removed from note: $normalizedTag');
      return updatedNote;
    }
    return null;
  }

  /// Get notes by tag
  Future<List<Note>> listNotesByTag(String tag) async {
    final notes = await listNotes();
    final normalizedTag = tag.trim().toLowerCase();
    return notes.where((note) => note.tags.contains(normalizedTag)).toList();
  }

  /// Get all unique tags across all notes
  Future<List<String>> getAllTags() async {
    final notes = await listNotes();
    final tagSet = <String>{};
    for (final note in notes) {
      tagSet.addAll(note.tags);
    }
    final tagList = tagSet.toList();
    tagList.sort();
    return tagList;
  }
}
