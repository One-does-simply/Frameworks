/// A single entry in the application's navigation menu.
///
/// ODS Spec alignment: Maps to items in the top-level `menu` array. Each item
/// has a display label and a target page ID.
///
/// ODS Ethos: Navigation is flat — every menu item maps directly to a page.
/// When multi-user is enabled, menu items can be restricted to specific roles.
class OdsMenuItem {
  /// The text displayed in the navigation drawer.
  final String label;

  /// The page ID this menu item navigates to.
  final String mapsTo;

  /// Optional role restriction. When set, only users with a matching role
  /// can see this menu item. When null/empty, visible to everyone.
  final List<String>? roles;

  const OdsMenuItem({required this.label, required this.mapsTo, this.roles});

  factory OdsMenuItem.fromJson(Map<String, dynamic> json) {
    return OdsMenuItem(
      label: json['label'] as String,
      mapsTo: json['mapsTo'] as String,
      roles: (json['roles'] as List<dynamic>?)?.cast<String>(),
    );
  }
}
