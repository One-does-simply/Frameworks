import 'ods_app_setting.dart';
import 'ods_auth.dart';
import 'ods_branding.dart';
import 'ods_data_source.dart';
import 'ods_help.dart';
import 'ods_menu_item.dart';
import 'ods_page.dart';

/// The top-level model representing a complete ODS application.
///
/// ODS Spec alignment: This is the root object of ods-schema.json. It holds
/// everything the framework needs to render a full application: metadata
/// (appName), navigation (startPage, menu), content (pages), data layer
/// (dataSources), and user guidance (help, tour).
///
/// ODS Ethos: One JSON file = one complete application. No external config,
/// no build steps, no server. This model captures that entire contract.
///
/// Architecture note: This class lives in the models layer and has ZERO
/// Flutter imports. It is pure Dart, making it reusable by future non-Flutter
/// ODS frameworks and by the planned code-generation off-ramp.
class OdsApp {
  final String appName;

  /// The default start page ID (used when no role-specific page matches).
  final String startPage;

  /// Role-based start page overrides. When the spec's `startPage` is an
  /// object, each key is a role and the value is the page ID for that role.
  /// The `default` key is stored in [startPage].
  final Map<String, String> startPageByRole;

  /// Navigation menu entries shown in the drawer.
  /// Optional: apps with a single page may omit the menu.
  final List<OdsMenuItem> menu;

  /// All pages in the app, keyed by page ID.
  final Map<String, OdsPage> pages;

  /// All data sources, keyed by a unique identifier referenced by
  /// list components and submit actions.
  final Map<String, OdsDataSource> dataSources;

  /// Optional in-app help content (overview + per-page contextual help).
  final OdsHelp? help;

  /// Optional guided tour steps shown on first launch.
  final List<OdsTourStep> tour;

  /// Optional user-configurable settings with default values.
  final Map<String, OdsAppSetting> settings;

  /// Authentication and role-based access control configuration.
  /// When absent or `multiUser: false`, the app runs in single-user mode.
  final OdsAuth auth;

  /// Visual branding and theming configuration.
  final OdsBranding branding;

  /// Resolves the start page for the given roles. Returns the first
  /// role-specific match, or falls back to [startPage].
  String startPageForRoles(List<String> roles) {
    for (final role in roles) {
      final page = startPageByRole[role];
      if (page != null) return page;
    }
    return startPage;
  }

  const OdsApp({
    required this.appName,
    required this.startPage,
    this.startPageByRole = const {},
    required this.menu,
    required this.pages,
    required this.dataSources,
    this.help,
    this.tour = const [],
    this.settings = const {},
    this.auth = const OdsAuth(),
    this.branding = const OdsBranding(),
  });

  factory OdsApp.fromJson(Map<String, dynamic> json) {
    // startPage can be a string or an object with role-based mappings
    final rawStartPage = json['startPage'];
    final String startPage;
    final Map<String, String> startPageByRole;
    if (rawStartPage is Map) {
      final map = Map<String, String>.from(rawStartPage.map(
        (k, v) => MapEntry(k as String, v as String),
      ));
      startPage = map.remove('default') ?? map.values.first;
      startPageByRole = map;
    } else {
      startPage = rawStartPage as String;
      startPageByRole = const {};
    }

    return OdsApp(
      appName: json['appName'] as String,
      startPage: startPage,
      startPageByRole: startPageByRole,
      // Menu is optional — default to empty list if not provided.
      menu: (json['menu'] as List<dynamic>?)
              ?.map((m) => OdsMenuItem.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
      pages: (json['pages'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, OdsPage.fromJson(value as Map<String, dynamic>)),
      ),
      // DataSources are optional — apps with only static text don't need them.
      dataSources: (json['dataSources'] as Map<String, dynamic>?)?.map(
            (key, value) =>
                MapEntry(key, OdsDataSource.fromJson(value as Map<String, dynamic>)),
          ) ??
          {},
      help: json['help'] != null
          ? OdsHelp.fromJson(json['help'] as Map<String, dynamic>)
          : null,
      tour: (json['tour'] as List<dynamic>?)
              ?.map((t) => OdsTourStep.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      settings: (json['settings'] as Map<String, dynamic>?)?.map(
            (key, value) =>
                MapEntry(key, OdsAppSetting.fromJson(value as Map<String, dynamic>)),
          ) ??
          {},
      auth: OdsAuth.fromJson(json['auth'] as Map<String, dynamic>?),
      branding: OdsBranding.fromJson(json['branding'] as Map<String, dynamic>?),
    );
  }
}
