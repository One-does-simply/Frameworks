import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';

/// Supported export formats.
enum ExportFormat {
  json('JSON', 'json', 'Standard JSON — works with any programming language'),
  csv('CSV', 'csv', 'Comma-separated values — opens in Excel, Sheets, etc.'),
  sql('SQL', 'sql', 'SQL INSERT statements — import into any database');

  final String label;
  final String extension;
  final String description;
  const ExportFormat(this.label, this.extension, this.description);
}

/// Converts exported table data into various file formats and saves to disk.
class DataExporter {
  /// Exports data in the chosen format, presenting a save dialog to the user.
  /// Returns the output path on success, or null if cancelled/failed.
  Future<String?> export({
    required String appName,
    required Map<String, dynamic> exportData,
    required ExportFormat format,
  }) async {
    final tables = exportData['tables'] as Map<String, dynamic>;
    final safeName = appName.replaceAll(RegExp(r'[^\w]'), '_').toLowerCase();

    switch (format) {
      case ExportFormat.json:
        return _exportJson(safeName, exportData);
      case ExportFormat.csv:
        return _exportCsv(safeName, tables);
      case ExportFormat.sql:
        return _exportSql(safeName, tables);
    }
  }

  // ---------------------------------------------------------------------------
  // JSON export
  // ---------------------------------------------------------------------------

  Future<String?> _exportJson(String safeName, Map<String, dynamic> data) async {
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export as JSON',
      fileName: '${safeName}_export.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (path == null) return null;
    await File(path).writeAsString(jsonString);
    return path;
  }

  // ---------------------------------------------------------------------------
  // CSV export — one file per table, zipped if multiple tables
  // ---------------------------------------------------------------------------

  Future<String?> _exportCsv(String safeName, Map<String, dynamic> tables) async {
    final csvFiles = <String, String>{};

    for (final entry in tables.entries) {
      final tableName = entry.key;
      final rows = entry.value as List<dynamic>;
      if (rows.isEmpty) {
        csvFiles[tableName] = '';
        continue;
      }

      final allRows = rows.cast<Map<String, dynamic>>();
      // Collect all column names across all rows (order: first row keys + any extras).
      final columns = <String>{};
      for (final row in allRows) {
        columns.addAll(row.keys);
      }
      // Remove internal columns.
      final columnList = columns.where((c) => c != '_id').toList();

      final buffer = StringBuffer();
      // Header row
      buffer.writeln(columnList.map(_csvEscape).join(','));
      // Data rows
      for (final row in allRows) {
        buffer.writeln(columnList.map((col) => _csvEscape(row[col]?.toString() ?? '')).join(','));
      }
      csvFiles[tableName] = buffer.toString();
    }

    if (csvFiles.length == 1) {
      // Single table — save as plain .csv
      final tableName = csvFiles.keys.first;
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export as CSV',
        fileName: '${safeName}_$tableName.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (path == null) return null;
      await File(path).writeAsString(csvFiles.values.first);
      return path;
    } else {
      // Multiple tables — zip them
      return _saveAsZip(
        safeName: safeName,
        files: csvFiles.map((name, content) => MapEntry('$name.csv', utf8.encode(content))),
        dialogTitle: 'Export as CSV (ZIP)',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // SQL export — CREATE TABLE + INSERT statements
  // ---------------------------------------------------------------------------

  Future<String?> _exportSql(String safeName, Map<String, dynamic> tables) async {
    final buffer = StringBuffer();
    buffer.writeln('-- ODS Data Export: $safeName');
    buffer.writeln('-- Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln();

    for (final entry in tables.entries) {
      final tableName = entry.key;
      final rows = entry.value as List<dynamic>;
      if (rows.isEmpty) {
        buffer.writeln('-- Table "$tableName" is empty');
        buffer.writeln();
        continue;
      }

      final allRows = rows.cast<Map<String, dynamic>>();
      final columns = <String>{};
      for (final row in allRows) {
        columns.addAll(row.keys);
      }
      final columnList = columns.where((c) => c != '_id').toList();

      // CREATE TABLE
      buffer.writeln('CREATE TABLE IF NOT EXISTS "$tableName" (');
      buffer.writeln('  _id TEXT PRIMARY KEY,');
      for (var i = 0; i < columnList.length; i++) {
        final comma = i < columnList.length - 1 ? ',' : '';
        buffer.writeln('  "${columnList[i]}" TEXT$comma');
      }
      buffer.writeln(');');
      buffer.writeln();

      // INSERT statements
      for (final row in allRows) {
        final values = columnList.map((col) {
          final val = row[col];
          if (val == null) return 'NULL';
          return "'${val.toString().replaceAll("'", "''")}'";
        }).join(', ');
        final colNames = columnList.map((c) => '"$c"').join(', ');
        buffer.writeln('INSERT INTO "$tableName" ($colNames) VALUES ($values);');
      }
      buffer.writeln();
    }

    final sql = buffer.toString();
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export as SQL',
      fileName: '${safeName}_export.sql',
      type: FileType.custom,
      allowedExtensions: ['sql'],
    );
    if (path == null) return null;
    await File(path).writeAsString(sql);
    return path;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Escapes a value for CSV (quotes strings containing commas, quotes, or newlines).
  String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Saves multiple files as a ZIP archive via a save dialog.
  Future<String?> _saveAsZip({
    required String safeName,
    required Map<String, List<int>> files,
    required String dialogTitle,
  }) async {
    final archive = Archive();
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) return null;

    final path = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: '${safeName}_export.zip',
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (path == null) return null;
    await File(path).writeAsBytes(zipBytes);
    return path;
  }
}
