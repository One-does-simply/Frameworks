import 'ods_component.dart';

/// A single page (screen) in an ODS application.
///
/// ODS Spec alignment: Maps to entries in the `pages` dictionary. Each page
/// has a title and an ordered array of components that define its content.
///
/// ODS Ethos: Pages are the only organizational unit. No tabs, no modals,
/// no nested layouts. Each page is a simple top-to-bottom stack of components.
/// This makes apps predictable for both the builder and the end user.
class OdsPage {
  /// The display title shown in the app bar.
  final String title;

  /// Ordered list of components rendered top-to-bottom on this page.
  final List<OdsComponent> content;

  /// Optional role restriction. When set, only users with a matching role
  /// can access this page. When null/empty, accessible to everyone.
  final List<String>? roles;

  const OdsPage({required this.title, required this.content, this.roles});

  factory OdsPage.fromJson(Map<String, dynamic> json) {
    return OdsPage(
      title: json['title'] as String,
      content: (json['content'] as List<dynamic>)
          .map((c) => OdsComponent.fromJson(c as Map<String, dynamic>))
          .toList(),
      roles: (json['roles'] as List<dynamic>?)?.cast<String>(),
    );
  }
}
