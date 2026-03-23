import 'ods_field_definition.dart';
import 'ods_ownership.dart';

/// Defines a data endpoint — either local SQLite storage or an external API.
///
/// ODS Spec alignment: Maps to entries in the `dataSources` dictionary.
/// The `local://` URL convention signals framework-managed storage:
///   - `local://<tableName>` with method GET → read all rows
///   - `local://<tableName>` with method POST → insert a new row
///
/// ODS Ethos: The `local://` convention is the heart of "no backend required."
/// Citizen developers describe *what* data they want stored, and the framework
/// handles *how*. No database config, no connection strings, no migrations.
/// Data stays on-device — private by default.
class OdsDataSource {
  /// The data endpoint URL. Use `local://<tableName>` for on-device storage
  /// or a full URL (https://) for external APIs.
  final String url;

  /// The access method: "GET" to read, "POST" to write.
  final String method;

  /// Optional explicit field definitions for a local:// source.
  /// When present, the framework creates the table with these columns upfront.
  /// When absent, the schema is auto-inferred from the first form submission
  /// — the "form is the schema" pattern.
  final List<OdsFieldDefinition>? fields;

  /// Optional seed data to pre-populate the table on first creation.
  /// Only inserted when the table is empty, so user data is never overwritten.
  final List<Map<String, dynamic>>? seedData;

  /// Optional row-level security configuration. When enabled, the framework
  /// auto-injects the current user's ID on insert and filters queries.
  final OdsOwnership ownership;

  const OdsDataSource({
    required this.url,
    required this.method,
    this.fields,
    this.seedData,
    this.ownership = const OdsOwnership(),
  });

  /// Whether this source uses framework-managed local storage.
  bool get isLocal => url.startsWith('local://');

  /// Extracts the SQLite table name from a `local://` URL.
  String get tableName {
    if (!isLocal) return '';
    return url.substring('local://'.length);
  }

  factory OdsDataSource.fromJson(Map<String, dynamic> json) {
    return OdsDataSource(
      url: json['url'] as String,
      method: json['method'] as String,
      fields: (json['fields'] as List<dynamic>?)
          ?.map((f) => OdsFieldDefinition.fromJson(f as Map<String, dynamic>))
          .toList(),
      seedData: (json['seedData'] as List<dynamic>?)
          ?.map((d) => Map<String, dynamic>.from(d as Map))
          .toList(),
      ownership: OdsOwnership.fromJson(json['ownership'] as Map<String, dynamic>?),
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'method': method,
        if (fields != null) 'fields': fields!.map((f) => f.toJson()).toList(),
        if (seedData != null) 'seedData': seedData,
        if (ownership.enabled) 'ownership': ownership.toJson(),
      };
}
