import 'dart:ui';

/// Table element that can be placed on the canvas
class CanvasTable {
  final String id;
  final Offset position; // Top-left position on canvas
  final int rows;
  final int columns;
  final double cellWidth; // Default cell width (used when columnWidths is null)
  final double cellHeight; // Default cell height (used when rowHeights is null)
  final List<double>? columnWidths; // Individual column widths
  final List<double>? rowHeights; // Individual row heights
  final Color borderColor;
  final double borderWidth;
  final List<List<String>> cellContents; // Content for each cell
  final int timestamp;

  CanvasTable({
    required this.id,
    required this.position,
    required this.rows,
    required this.columns,
    this.cellWidth = 80.0,
    this.cellHeight = 30.0,
    this.columnWidths,
    this.rowHeights,
    this.borderColor = const Color(0xFF000000),
    this.borderWidth = 1.0,
    List<List<String>>? cellContents,
    required this.timestamp,
  }) : cellContents = cellContents ??
         List.generate(rows, (_) => List.generate(columns, (_) => ''));

  /// Get width of a specific column
  double getColumnWidth(int col) {
    if (columnWidths != null && col >= 0 && col < columnWidths!.length) {
      return columnWidths![col];
    }
    return cellWidth;
  }

  /// Get height of a specific row
  double getRowHeight(int row) {
    if (rowHeights != null && row >= 0 && row < rowHeights!.length) {
      return rowHeights![row];
    }
    return cellHeight;
  }

  /// Get X position of a column (left edge)
  double getColumnX(int col) {
    double x = position.dx;
    for (int i = 0; i < col; i++) {
      x += getColumnWidth(i);
    }
    return x;
  }

  /// Get Y position of a row (top edge)
  double getRowY(int row) {
    double y = position.dy;
    for (int i = 0; i < row; i++) {
      y += getRowHeight(i);
    }
    return y;
  }

  /// Get total width of the table
  double get width {
    if (columnWidths != null) {
      return columnWidths!.fold(0.0, (sum, w) => sum + w);
    }
    return columns * cellWidth;
  }

  /// Get total height of the table
  double get height {
    if (rowHeights != null) {
      return rowHeights!.fold(0.0, (sum, h) => sum + h);
    }
    return rows * cellHeight;
  }

  /// Get total size of the table
  Size get size => Size(width, height);

  /// Get bounding rectangle
  Rect get bounds => Rect.fromLTWH(position.dx, position.dy, width, height);

  /// Check if a point is inside this table
  bool containsPoint(Offset point) {
    return bounds.contains(point);
  }

  /// Check if a point is near the border of this table (for eraser detection)
  /// Returns true if point is within tolerance of any border line
  bool isNearBorder(Offset point, {double tolerance = 20.0}) {
    final rect = bounds;

    // Check if point is near left edge
    if (point.dy >= rect.top - tolerance && point.dy <= rect.bottom + tolerance) {
      if ((point.dx - rect.left).abs() <= tolerance) return true;
      if ((point.dx - rect.right).abs() <= tolerance) return true;
    }

    // Check if point is near top/bottom edge
    if (point.dx >= rect.left - tolerance && point.dx <= rect.right + tolerance) {
      if ((point.dy - rect.top).abs() <= tolerance) return true;
      if ((point.dy - rect.bottom).abs() <= tolerance) return true;
    }

    // Check internal grid lines
    // Vertical lines (column borders)
    if (point.dy >= rect.top - tolerance && point.dy <= rect.bottom + tolerance) {
      double x = position.dx;
      for (int i = 0; i < columns; i++) {
        x += getColumnWidth(i);
        if ((point.dx - x).abs() <= tolerance) return true;
      }
    }

    // Horizontal lines (row borders)
    if (point.dx >= rect.left - tolerance && point.dx <= rect.right + tolerance) {
      double y = position.dy;
      for (int i = 0; i < rows; i++) {
        y += getRowHeight(i);
        if ((point.dy - y).abs() <= tolerance) return true;
      }
    }

    return false;
  }

  /// Get the cell at a specific point
  ({int row, int col})? getCellAt(Offset point) {
    if (!containsPoint(point)) return null;

    // Find column
    double x = position.dx;
    int col = 0;
    for (int i = 0; i < columns; i++) {
      final w = getColumnWidth(i);
      if (point.dx < x + w) {
        col = i;
        break;
      }
      x += w;
      if (i == columns - 1) col = i;
    }

    // Find row
    double y = position.dy;
    int row = 0;
    for (int i = 0; i < rows; i++) {
      final h = getRowHeight(i);
      if (point.dy < y + h) {
        row = i;
        break;
      }
      y += h;
      if (i == rows - 1) row = i;
    }

    return (row: row, col: col);
  }

  /// Get the bounds of a specific cell
  Rect getCellBounds(int row, int col) {
    return Rect.fromLTWH(
      getColumnX(col),
      getRowY(row),
      getColumnWidth(col),
      getRowHeight(row),
    );
  }

  /// Check if a point is on the left edge of the table (for drag detection)
  /// Returns true if point is within tolerance of the left border
  bool isOnLeftEdge(Offset point, {double tolerance = 1.5}) {
    // Check if Y is within table height (strict 1.5px margin)
    if (point.dy < position.dy - 1.5 || point.dy > position.dy + height + 1.5) {
      return false;
    }
    // Check if X is near the left edge (strict tolerance)
    return (point.dx - position.dx).abs() <= tolerance;
  }

  /// Check if a point is on the top edge of the table (for height resize)
  /// Returns true if point is within tolerance of the top border
  bool isOnTopEdge(Offset point, {double tolerance = 1.5}) {
    // Check if X is within table width (strict 1.5px margin)
    if (point.dx < position.dx - 1.5 || point.dx > position.dx + width + 1.5) {
      return false;
    }
    // Check if Y is near the top edge (strict tolerance)
    return (point.dy - position.dy).abs() <= tolerance;
  }

  /// Check if a point is near a column border (for resize detection)
  /// Returns column index (right border of that column) or -1 if not near any border
  int getColumnBorderAt(Offset point, {double tolerance = 1.5}) {
    if (point.dy < position.dy || point.dy > position.dy + height) return -1;

    double x = position.dx;
    for (int i = 0; i < columns; i++) {
      x += getColumnWidth(i);
      if ((point.dx - x).abs() <= tolerance) {
        return i; // Return the column whose right border is being touched
      }
    }
    return -1;
  }

  /// Check if a point is near a row border (for resize detection)
  /// Returns row index (bottom border of that row) or -1 if not near any border
  int getRowBorderAt(Offset point, {double tolerance = 1.5}) {
    if (point.dx < position.dx || point.dx > position.dx + width) return -1;

    double y = position.dy;
    for (int i = 0; i < rows; i++) {
      y += getRowHeight(i);
      if ((point.dy - y).abs() <= tolerance) {
        return i; // Return the row whose bottom border is being touched
      }
    }
    return -1;
  }

  /// Create a copy with updated column width
  CanvasTable withColumnWidth(int col, double newWidth) {
    if (col < 0 || col >= columns) return this;
    final newWidths = columnWidths != null
        ? List<double>.from(columnWidths!)
        : List<double>.generate(columns, (i) => cellWidth);
    newWidths[col] = newWidth.clamp(20.0, 500.0); // Min 20, max 500
    return copyWith(columnWidths: newWidths);
  }

  /// Create a copy with updated row height
  CanvasTable withRowHeight(int row, double newHeight) {
    if (row < 0 || row >= rows) return this;
    final newHeights = rowHeights != null
        ? List<double>.from(rowHeights!)
        : List<double>.generate(rows, (i) => cellHeight);
    newHeights[row] = newHeight.clamp(15.0, 300.0); // Min 15, max 300
    return copyWith(rowHeights: newHeights);
  }

  CanvasTable copyWith({
    String? id,
    Offset? position,
    int? rows,
    int? columns,
    double? cellWidth,
    double? cellHeight,
    List<double>? columnWidths,
    List<double>? rowHeights,
    Color? borderColor,
    double? borderWidth,
    List<List<String>>? cellContents,
    int? timestamp,
  }) {
    return CanvasTable(
      id: id ?? this.id,
      position: position ?? this.position,
      rows: rows ?? this.rows,
      columns: columns ?? this.columns,
      cellWidth: cellWidth ?? this.cellWidth,
      cellHeight: cellHeight ?? this.cellHeight,
      columnWidths: columnWidths ?? (this.columnWidths != null ? List<double>.from(this.columnWidths!) : null),
      rowHeights: rowHeights ?? (this.rowHeights != null ? List<double>.from(this.rowHeights!) : null),
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      cellContents: cellContents ??
          this.cellContents.map((row) => List<String>.from(row)).toList(),
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Update cell content at specific position
  CanvasTable updateCellContent(int row, int col, String content) {
    if (row < 0 || row >= rows || col < 0 || col >= columns) return this;

    final newContents = cellContents.map((r) => List<String>.from(r)).toList();
    newContents[row][col] = content;

    return copyWith(cellContents: newContents);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'positionX': position.dx,
      'positionY': position.dy,
      'rows': rows,
      'columns': columns,
      'cellWidth': cellWidth,
      'cellHeight': cellHeight,
      'columnWidths': columnWidths,
      'rowHeights': rowHeights,
      'borderColor': borderColor.value,
      'borderWidth': borderWidth,
      'cellContents': cellContents,
      'timestamp': timestamp,
    };
  }

  factory CanvasTable.fromJson(Map<String, dynamic> json) {
    final rows = json['rows'] as int;
    final columns = json['columns'] as int;
    final cellContentsJson = json['cellContents'] as List<dynamic>?;

    List<List<String>> cellContents;
    if (cellContentsJson != null) {
      cellContents = cellContentsJson
          .map((row) => (row as List<dynamic>).map((cell) => cell as String).toList())
          .toList();
    } else {
      cellContents = List.generate(rows, (_) => List.generate(columns, (_) => ''));
    }

    // Parse columnWidths
    final columnWidthsJson = json['columnWidths'] as List<dynamic>?;
    List<double>? columnWidths;
    if (columnWidthsJson != null) {
      columnWidths = columnWidthsJson.map((w) => (w as num).toDouble()).toList();
    }

    // Parse rowHeights
    final rowHeightsJson = json['rowHeights'] as List<dynamic>?;
    List<double>? rowHeights;
    if (rowHeightsJson != null) {
      rowHeights = rowHeightsJson.map((h) => (h as num).toDouble()).toList();
    }

    return CanvasTable(
      id: json['id'] as String,
      position: Offset(
        (json['positionX'] as num).toDouble(),
        (json['positionY'] as num).toDouble(),
      ),
      rows: rows,
      columns: columns,
      cellWidth: (json['cellWidth'] as num?)?.toDouble() ?? 80.0,
      cellHeight: (json['cellHeight'] as num?)?.toDouble() ?? 30.0,
      columnWidths: columnWidths,
      rowHeights: rowHeights,
      borderColor: Color(json['borderColor'] as int? ?? 0xFF000000),
      borderWidth: (json['borderWidth'] as num?)?.toDouble() ?? 1.0,
      cellContents: cellContents,
      timestamp: json['timestamp'] as int,
    );
  }

  @override
  String toString() => 'CanvasTable(id: $id, ${rows}x$columns, position: $position)';
}
