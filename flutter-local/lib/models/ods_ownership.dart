/// Defines row-level security (ownership) for a data source.
///
/// ODS Spec alignment: Maps to the optional `ownership` object on dataSource
/// definitions. When enabled, the framework auto-injects the current user's ID
/// on insert and filters queries to only return rows owned by the current user.
///
/// ODS Ethos: Row-level security is opt-in per table, off by default.
/// Builders add `"ownership": { "enabled": true }` and the framework handles
/// the rest — no SQL, no WHERE clauses, no middleware config.
class OdsOwnership {
  /// When true, the framework enforces row-level ownership on this data source.
  final bool enabled;

  /// The column name that stores the owner's user ID.
  /// Defaults to "_owner". Auto-created and auto-populated by the framework.
  final String ownerField;

  /// When true (default), admin users bypass ownership filters and can see
  /// all rows. When false, even admins only see their own rows.
  final bool adminOverride;

  const OdsOwnership({
    this.enabled = false,
    this.ownerField = '_owner',
    this.adminOverride = true,
  });

  factory OdsOwnership.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const OdsOwnership();
    return OdsOwnership(
      enabled: json['enabled'] as bool? ?? false,
      ownerField: json['ownerField'] as String? ?? '_owner',
      adminOverride: json['adminOverride'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        if (ownerField != '_owner') 'ownerField': ownerField,
        if (!adminOverride) 'adminOverride': adminOverride,
      };
}
