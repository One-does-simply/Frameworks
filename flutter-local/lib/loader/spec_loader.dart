import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Provides three ways to obtain an ODS JSON spec string.
///
/// ODS Spec: The spec is just a JSON file. It can live anywhere — on the
/// user's device, at a URL, or bundled inside the framework itself.
///
/// ODS Ethos: "Bring your own spec." The framework never phones home and
/// never requires an account. These three loaders cover the full spectrum
/// from fully offline (file picker / bundled) to fetch-once-and-done (URL).
///
/// Each method returns a raw JSON string that will later be handed to
/// [SpecParser] for deserialization and [SpecValidator] for validation.
class SpecLoader {
  /// Opens a native file picker filtered to `.json` files.
  ///
  /// Returns the file contents as a string, or `null` if the user cancelled.
  /// Handles two platform cases:
  ///   - Desktop / mobile with file system access: reads via [File.readAsString].
  ///   - Web / sandboxed platforms: reads from the in-memory byte buffer.
  Future<String?> loadFromFilePicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: 'Select an ODS Specification File',
    );

    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    // Prefer the file path (available on desktop / mobile with storage access).
    if (file.path != null) {
      return File(file.path!).readAsString();
    }
    // Fall back to the in-memory byte buffer (web, sandboxed environments).
    if (file.bytes != null) {
      return String.fromCharCodes(file.bytes!);
    }
    return null;
  }

  /// Fetches a spec from a remote URL via a simple HTTP GET.
  ///
  /// Throws an [Exception] on non-200 responses so the caller can display
  /// a meaningful error to the user.
  Future<String> loadFromUrl(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to load spec from URL: HTTP ${response.statusCode}');
    }
    return response.body;
  }

  /// Loads a spec that is bundled as a Flutter asset (e.g. example apps).
  ///
  /// Asset paths are declared in `pubspec.yaml` and compiled into the binary.
  /// This is how the six built-in example apps are shipped with the framework.
  Future<String> loadBundledAsset(String assetPath) async {
    return rootBundle.loadString(assetPath);
  }
}
