/// In-app help content defined by the spec author.
///
/// ODS Spec alignment: Maps to the top-level `help` object in ods-schema.json.
/// Contains an overview and optional per-page contextual help text.
///
/// ODS Ethos: Help is part of the spec, not an afterthought. Because ODS apps
/// are built by citizen developers who may not write separate documentation,
/// embedding help directly in the spec ensures every app is self-documenting.
class OdsHelp {
  /// A general description of what the app does and how to use it.
  final String overview;

  /// Per-page help text, keyed by page ID. Shown as a contextual banner
  /// at the top of each page in the framework.
  final Map<String, String> pages;

  const OdsHelp({required this.overview, this.pages = const {}});

  factory OdsHelp.fromJson(Map<String, dynamic> json) {
    return OdsHelp(
      overview: json['overview'] as String,
      pages: (json['pages'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(key, value as String),
          ) ??
          const {},
    );
  }
}

/// A single step in the guided tour shown on first launch.
///
/// ODS Spec alignment: Maps to items in the top-level `tour` array.
/// Each step has a title, explanatory content, and an optional page reference
/// that causes the framework to navigate as the tour progresses.
///
/// ODS Ethos: A good tour eliminates the need for a manual. The spec author
/// walks the user through the app once, and then the app speaks for itself.
class OdsTourStep {
  final String title;
  final String content;

  /// Optional page ID to navigate to when this step is shown.
  /// Lets the user see the relevant page while the tour explains it.
  final String? page;

  const OdsTourStep({required this.title, required this.content, this.page});

  factory OdsTourStep.fromJson(Map<String, dynamic> json) {
    return OdsTourStep(
      title: json['title'] as String,
      content: json['content'] as String,
      page: json['page'] as String?,
    );
  }
}
