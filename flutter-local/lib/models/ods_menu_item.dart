/// A single entry in the application's navigation menu.
///
/// ODS Spec alignment: Maps to items in the top-level `menu` array. Each item
/// has a display label and a target page ID.
///
/// ODS Ethos: Navigation is flat — every menu item maps directly to a page.
/// No nested menus, no dropdowns, no role-based visibility. If the user can
/// see it, they can tap it. Simple.
class OdsMenuItem {
  /// The text displayed in the navigation drawer.
  final String label;

  /// The page ID this menu item navigates to.
  final String mapsTo;

  const OdsMenuItem({required this.label, required this.mapsTo});

  factory OdsMenuItem.fromJson(Map<String, dynamic> json) {
    return OdsMenuItem(
      label: json['label'] as String,
      mapsTo: json['mapsTo'] as String,
    );
  }
}
