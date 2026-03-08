import 'dart:convert';

import '../models/ods_app.dart';
import 'spec_validator.dart';

/// The result of parsing an ODS spec JSON string.
///
/// Contains the parsed [OdsApp] model (if successful), validation messages,
/// and any hard parse error that prevented model construction.
class ParseResult {
  final OdsApp? app;
  final ValidationResult validation;
  final String? parseError;

  const ParseResult({this.app, required this.validation, this.parseError});

  /// True when the spec parsed successfully with no validation errors.
  /// Warnings are allowed — they appear in debug mode but don't block loading.
  bool get isOk => app != null && !validation.hasErrors;
}

/// Parses a raw JSON string into an [OdsApp] model with validation.
///
/// ODS Spec alignment: This is the system boundary where raw JSON enters the
/// framework. Parsing follows a two-phase approach:
///   1. Structural validation: checks required top-level fields (appName,
///      startPage, pages) before attempting to construct the model.
///   2. Semantic validation: once the model is built, the [SpecValidator]
///      checks cross-references (menu targets, data source references, etc.).
///
/// ODS Ethos: Best-effort rendering. If the JSON is valid and has the required
/// fields, the app loads — even if there are warnings. This lets citizen
/// developers iterate quickly without being blocked by minor issues.
class SpecParser {
  final SpecValidator _validator = SpecValidator();

  ParseResult parse(String jsonString) {
    final validation = ValidationResult();

    // Phase 1: Decode JSON and check required top-level fields.
    Map<String, dynamic> json;
    try {
      json = jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      return ParseResult(
        validation: validation,
        parseError: 'Invalid JSON: $e',
      );
    }

    if (!json.containsKey('appName')) {
      validation.error('Missing required field: appName');
    }
    if (!json.containsKey('startPage')) {
      validation.error('Missing required field: startPage');
    }
    if (!json.containsKey('pages')) {
      validation.error('Missing required field: pages');
    }

    // Bail early if required fields are missing — can't build a model.
    if (validation.hasErrors) {
      return ParseResult(validation: validation);
    }

    // Phase 2: Construct the model tree from JSON.
    OdsApp app;
    try {
      app = OdsApp.fromJson(json);
    } catch (e) {
      return ParseResult(
        validation: validation,
        parseError: 'Failed to parse spec: $e',
      );
    }

    // Phase 3: Semantic validation of cross-references.
    final fullValidation = _validator.validate(app);
    return ParseResult(app: app, validation: fullValidation);
  }
}
