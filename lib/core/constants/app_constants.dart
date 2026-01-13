class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'Winote';
  static const String appVersion = '1.0.0';

  // Canvas Settings
  static const double defaultStrokeWidth = 2.0;
  static const double minStrokeWidth = 0.5;
  static const double maxStrokeWidth = 20.0;
  static const double minZoom = 0.5;
  static const double maxZoom = 5.0;

  // Tile Cache
  static const int tileSize = 256;
  static const int maxCachedTiles = 100;

  // Spatial Index
  static const int quadTreeMaxDepth = 8;
  static const int quadTreeMaxObjects = 10;

  // Auto Save
  static const int autoSaveDelayMs = 3000;

  // Performance
  static const int maxUndoHistory = 100;
  static const double resampleDistance = 2.5;
  static const double minPointDistance = 1.0;

  // File Extensions
  static const String strokeFileExtension = '.strokes.bin';
  static const String noteFileExtension = '.json';
  static const String thumbnailExtension = '.png';

  // Storage Paths
  static const String notebooksFolder = 'notebooks';
  static const String attachmentsFolder = 'attachments';
  static const String metadataFolder = '.winote';
}
