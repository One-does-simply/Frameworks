/// Defines multi-user authentication and role configuration for an ODS app.
///
/// ODS Spec alignment: Maps to the top-level `auth` object in ods-schema.json.
/// When `multiUser` is false (the default), the app runs in single-user mode
/// with no login screen, no roles, and no user tables — exactly as before.
///
/// ODS Ethos: Builders declare *what* roles exist and *whether* multi-user is on.
/// The framework handles *everything* else: login UI, user management, session
/// state, permission filtering, and row-level security.
class OdsAuth {
  /// When true, the framework enables login, user management, and role-based
  /// access control. When false (default), the app is single-user.
  final bool multiUser;

  /// When true, the app refuses to run without admin setup. The framework
  /// shows a setup wizard instead of the app content. When false, multi-user
  /// can be skipped (the app runs in single-user mode until configured).
  final bool multiUserOnly;

  /// Custom roles defined by the builder, beyond the three built-in roles
  /// (guest, user, admin). The built-in roles always exist implicitly.
  final List<String> customRoles;

  /// The role automatically assigned to newly registered users.
  /// Defaults to "user".
  final String defaultRole;

  /// All available roles: the three built-ins plus any custom roles.
  List<String> get allRoles => ['guest', 'user', 'admin', ...customRoles];

  const OdsAuth({
    this.multiUser = false,
    this.multiUserOnly = false,
    this.customRoles = const [],
    this.defaultRole = 'user',
  });

  factory OdsAuth.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const OdsAuth();
    return OdsAuth(
      multiUser: json['multiUser'] as bool? ?? false,
      multiUserOnly: json['multiUserOnly'] as bool? ?? false,
      customRoles: (json['roles'] as List<dynamic>?)?.cast<String>() ?? const [],
      defaultRole: json['defaultRole'] as String? ?? 'user',
    );
  }

  Map<String, dynamic> toJson() => {
        'multiUser': multiUser,
        if (multiUserOnly) 'multiUserOnly': multiUserOnly,
        if (customRoles.isNotEmpty) 'roles': customRoles,
        if (defaultRole != 'user') 'defaultRole': defaultRole,
      };
}
