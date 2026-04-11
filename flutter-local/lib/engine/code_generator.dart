import '../models/ods_app.dart';
import '../models/ods_component.dart';
import '../models/ods_data_source.dart';
import '../models/ods_field_definition.dart';
import '../models/ods_page.dart';

/// Generates a standalone Flutter project from an [OdsApp] spec.
///
/// ODS Off-Ramp: This is the escape hatch — when a citizen developer outgrows
/// the ODS framework, they can generate real Flutter source code that does
/// exactly what their spec does, then customize it freely.
///
/// The generated project is a self-contained Flutter app with:
///   - main.dart: MaterialApp with named routes and a drawer menu
///   - One widget file per page (forms, lists, buttons, charts)
///   - database_helper.dart: SQLite data layer with CRUD operations
///   - pubspec.yaml: All required dependencies
///   - analysis_options.yaml: Lint rules
class CodeGenerator {
  /// Generates all project files. Returns a map of relative path -> content.
  Map<String, String> generate(OdsApp app) {
    final files = <String, String>{};
    final packageName = _toSnakeCase(app.appName);

    files['README.md'] = _genReadme(app, packageName);
    files['pubspec.yaml'] = _genPubspec(app, packageName);
    files['analysis_options.yaml'] = _genAnalysisOptions();
    files['lib/main.dart'] = _genMain(app, packageName);
    files['lib/data/database_helper.dart'] = _genDatabaseHelper(app, packageName);
    files['lib/data/formula_evaluator.dart'] = _genFormulaEvaluator();
    if (app.settings.isNotEmpty || app.tour.isNotEmpty) {
      files['lib/data/app_settings.dart'] = _genAppSettings(app);
    }
    if (app.settings.isNotEmpty) {
      files['lib/screens/settings_dialog.dart'] = _genSettingsDialog(app);
    }
    if (app.help != null) {
      files['lib/screens/help_page.dart'] = _genHelpPage(app);
    }
    if (app.tour.isNotEmpty) {
      files['lib/screens/tour_dialog.dart'] = _genTourDialog(app);
    }

    for (final entry in app.pages.entries) {
      final fileName = _toSnakeCase(entry.key);
      files['lib/pages/${fileName}.dart'] =
          _genPage(entry.key, entry.value, app, packageName);
    }

    return files;
  }

  // ---------------------------------------------------------------------------
  // README.md
  // ---------------------------------------------------------------------------

  String _genReadme(OdsApp app, String packageName) {
    // Build the page list for the README
    final pageList = StringBuffer();
    for (final entry in app.pages.entries) {
      final page = entry.value;
      pageList.writeln('- **${page.title}** (`lib/pages/${_toSnakeCase(entry.key)}.dart`)');
    }

    // Build the file tree
    final fileTree = StringBuffer();
    fileTree.writeln('```');
    fileTree.writeln('$packageName/');
    fileTree.writeln('  README.md              <-- You are here');
    fileTree.writeln('  pubspec.yaml           <-- Project config and dependencies');
    fileTree.writeln('  analysis_options.yaml   <-- Dart lint rules');
    fileTree.writeln('  lib/');
    fileTree.writeln('    main.dart            <-- App entry point, routing, theme');
    fileTree.writeln('    data/');
    fileTree.writeln('      database_helper.dart  <-- SQLite database (creates tables, CRUD)');
    fileTree.writeln('    pages/');
    for (final entry in app.pages.entries) {
      final fileName = _toSnakeCase(entry.key);
      fileTree.writeln('      $fileName.dart');
    }
    fileTree.writeln('```');

    return '''
# ${app.appName}

This is a standalone Flutter app generated from an ODS (One Does Simply) spec.
**You own this code.** Edit anything you want — it's a normal Flutter project now.

---

## What You Need Before Starting

You need **two things** installed on your computer:

### 1. Flutter SDK

Flutter is the framework this app is built with. If you don't have it yet:

1. Go to **https://docs.flutter.dev/get-started/install**
2. Pick your operating system (Windows, macOS, or Linux)
3. Follow every step in their guide — it walks you through downloading Flutter,
   adding it to your PATH, and installing any extras (like Android Studio or
   Xcode) depending on which platform you want to run on
4. When done, open a terminal and run:
   ```
   flutter doctor
   ```
   This checks that everything is set up correctly. You want to see green
   checkmarks next to at least "Flutter" and one platform (like "Windows" or
   "Chrome").

### 2. A Code Editor

You need something to open and edit the code files. We recommend:

- **VS Code** (free): https://code.visualstudio.com/
  - After installing, add the "Flutter" extension (search for it in the
    Extensions panel on the left sidebar)
- **Android Studio** (free): https://developer.android.com/studio
  - Comes with Flutter support built in

---

## How to Run the App (Step by Step)

### Step 1: Open a Terminal

- **Windows**: Press `Win + R`, type `cmd`, press Enter. Or search for
  "Terminal" in the Start menu.
- **macOS**: Press `Cmd + Space`, type "Terminal", press Enter.
- **Linux**: Press `Ctrl + Alt + T`.

### Step 2: Navigate to the Project Folder

In the terminal, use the `cd` command to go to the folder where these files are.
For example, if you saved the project to your Desktop:

```
cd Desktop/$packageName
```

You'll know you're in the right folder when you can see `pubspec.yaml` by
running `ls` (macOS/Linux) or `dir` (Windows).

### Step 3: Set Up the Project

Run these two commands **in this order**:

```
flutter create .
```

This generates the platform-specific files that Flutter needs to build for
Windows, macOS, Linux, web, iOS, and Android. It will **not** overwrite any of
the code files that were already generated — it only adds the missing platform
folders (like `windows/`, `macos/`, `web/`, etc.).

You'll see output like "All done!" when it finishes.

Then run:

```
flutter pub get
```

This downloads all the libraries the app needs (like the database engine and
charting library). You'll see a bunch of output and then a success message.

**If you get an error** saying "flutter is not recognized", Flutter isn't in your
PATH yet. Go back to the Flutter install guide and complete the PATH setup step.

### Step 4: Run the App

Pick one of these depending on where you want to run it:

**On Windows (desktop window):**
```
flutter run -d windows
```

**On macOS (desktop window):**
```
flutter run -d macos
```

**On Linux (desktop window):**
```
flutter run -d linux
```

**In Chrome (web browser):**
```
flutter run -d chrome
```

**On a connected phone or emulator:**
```
flutter run
```
(Flutter will auto-detect your device)

The first build takes a minute or two — that's normal. After that, you'll see
your app appear!

### Step 5: Make Changes

Open the project folder in VS Code or Android Studio. Edit any file in the
`lib/` folder. If the app is still running in the terminal, press `r` to
**hot reload** (instant update) or `R` to **hot restart** (full restart).

---

## Project Structure

Here's what each file does:

${fileTree.toString()}
### main.dart

The app's entry point. Contains:
- **Database initialization** — sets up SQLite so data persists between sessions
- **MaterialApp** — the top-level Flutter widget that sets up the theme and routes
- **Routes** — maps page names to widgets (e.g., `'${app.startPage}'` opens the
  start page)

### database_helper.dart

Handles all data storage using SQLite. Contains:
- **Table creation** — automatically creates the database tables your app needs
- **Seed data** — pre-loads any sample data defined in the original spec
- **CRUD methods** — `getAll()`, `insert()`, `update()`, `delete()`

### Page files

Each page is its own widget file:

$pageList

Every page is a `StatefulWidget` with its own state. Forms have
`TextEditingController`s for each field, lists load data from the database, and
buttons handle navigation and data submission.

---

## Common Things You Might Want to Change

### Change the app's colors

In `lib/main.dart`, find the `ThemeData` section:
```dart
theme: ThemeData(
  colorSchemeSeed: Colors.blue,  // <-- Change this color
  useMaterial3: true,
),
```
Try `Colors.green`, `Colors.purple`, `Colors.orange`, etc.

### Change the app's title

In `lib/main.dart`, find the `title:` line:
```dart
title: '${app.appName}',  // <-- Change this string
```

### Add a new field to a form

Open the page file, find the `Form(...)` widget, and add a new `TextFormField`
inside the `children` list. Don't forget to:
1. Add a `TextEditingController` at the top of the state class
2. Dispose it in the `dispose()` method
3. Include it in the `insert()` call in the submit button

### Change what columns show in a list

Find the `DataTable(...)` widget in the page file. Edit the `DataColumn` list
to change headers, and the `DataCell` list to change which fields display.

---

## Troubleshooting

**"flutter: command not found"**
Flutter isn't in your system PATH. Re-run the Flutter installation steps for
your OS and make sure to complete the "Update your path" section.

**"No supported devices connected"**
You need to specify a target. Try `flutter run -d chrome` for web, or
`flutter run -d windows` (or `macos`/`linux`) for desktop.

**Build errors on first run**
Run `flutter clean` then `flutter pub get` then try again. This clears any
stale build files.

**Database seems empty**
The seed data only loads when the database is first created. If you've run the
app before and want fresh data, delete the app's database file (found in your
system's Documents folder) and restart.

---

## What's Next?

This generated code is a **starting point**. Some things you might want to add:

- **Custom chart styling** — charts are generated with fl_chart using basic
  styling; customize colors, labels, and tooltips to match your brand
- **Computed fields** — formulas from the ODS spec are noted in comments but
  need manual implementation
- **Conditional field visibility** — visibleWhen logic from the spec isn't
  generated yet; add `Visibility` widgets as needed
- **Filter dropdowns** — the original ODS app may have had filterable list
  columns; add `DropdownButton` widgets above the `DataTable`
- **Error handling** — add try/catch around database calls for production use
- **App icon and splash screen** — see the Flutter docs for customizing these

---

*Generated by One Does Simply (ODS) — the spec-driven app framework.*
*Learn more: https://github.com/your-org/one-does-simply*
''';
  }

  // ---------------------------------------------------------------------------
  // pubspec.yaml
  // ---------------------------------------------------------------------------

  String _genPubspec(OdsApp app, String packageName) {
    return '''
name: $packageName
description: Generated from ODS spec "${app.appName}"
publish_to: 'none'
version: 1.0.0

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
  sqflite_common_ffi: ^2.3.0
  path_provider: ^2.1.0
  path: ^1.8.0
  fl_chart: ^0.70.2
  intl: ^0.19.0
  shared_preferences: ^2.3.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

flutter:
  uses-material-design: true
''';
  }

  // ---------------------------------------------------------------------------
  // analysis_options.yaml
  // ---------------------------------------------------------------------------

  String _genAnalysisOptions() {
    return '''
include: package:flutter_lints/flutter.yaml
''';
  }

  // ---------------------------------------------------------------------------
  // main.dart
  // ---------------------------------------------------------------------------

  String _genMain(OdsApp app, String packageName) {
    final buf = StringBuffer();
    final needsAppSettings = app.settings.isNotEmpty || app.tour.isNotEmpty;

    // Imports
    buf.writeln("import 'package:flutter/material.dart';");
    buf.writeln("import 'package:sqflite_common_ffi/sqflite_ffi.dart';");
    if (needsAppSettings) {
      buf.writeln("import 'data/app_settings.dart';");
    }
    buf.writeln("import 'data/database_helper.dart';");
    for (final pageId in app.pages.keys) {
      buf.writeln("import 'pages/${_toSnakeCase(pageId)}.dart';");
    }
    buf.writeln();

    // main() — async to allow AppSettings initialization
    buf.writeln('void main() async {');
    buf.writeln('  WidgetsFlutterBinding.ensureInitialized();');
    buf.writeln('  sqfliteFfiInit();');
    buf.writeln('  databaseFactory = databaseFactoryFfi;');
    if (needsAppSettings) {
      buf.writeln('  await AppSettings.instance.initialize();');
    }
    buf.writeln('  runApp(const MyApp());');
    buf.writeln('}');
    buf.writeln();

    // MyApp widget — stateful so it can respond to theme-mode changes
    buf.writeln('class MyApp extends StatefulWidget {');
    buf.writeln('  const MyApp({super.key});');
    buf.writeln();
    buf.writeln('  /// Allows any descendant to change the app theme at runtime.');
    buf.writeln('  static _MyAppState of(BuildContext context) =>');
    buf.writeln('      context.findAncestorStateOfType<_MyAppState>()!;');
    buf.writeln();
    buf.writeln('  @override');
    buf.writeln('  State<MyApp> createState() => _MyAppState();');
    buf.writeln('}');
    buf.writeln();

    buf.writeln('class _MyAppState extends State<MyApp> {');
    buf.writeln('  ThemeMode _themeMode = ThemeMode.system;');
    buf.writeln();
    if (needsAppSettings) {
      buf.writeln('  @override');
      buf.writeln('  void initState() {');
      buf.writeln('    super.initState();');
      buf.writeln('    _themeMode = AppSettings.instance.getThemeMode();');
      buf.writeln('  }');
      buf.writeln();
    }
    buf.writeln('  void setThemeMode(ThemeMode mode) {');
    buf.writeln('    setState(() => _themeMode = mode);');
    buf.writeln('  }');
    buf.writeln();
    buf.writeln('  @override');
    buf.writeln('  Widget build(BuildContext context) {');
    buf.writeln('    return MaterialApp(');
    buf.writeln("      title: ${_dartString(app.appName)},");
    buf.writeln('      debugShowCheckedModeBanner: false,');
    buf.writeln('      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),');
    buf.writeln('      darkTheme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true, brightness: Brightness.dark),');
    buf.writeln('      themeMode: _themeMode,');
    buf.writeln("      initialRoute: ${_dartString(app.startPage)},");
    buf.writeln('      routes: {');
    for (final pageId in app.pages.keys) {
      final className = _toClassName(pageId);
      buf.writeln("        ${_dartString(pageId)}: (context) => const $className(),");
    }
    buf.writeln('      },');
    buf.writeln('    );');
    buf.writeln('  }');
    buf.writeln('}');

    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // database_helper.dart
  // ---------------------------------------------------------------------------

  String _genDatabaseHelper(OdsApp app, String packageName) {
    final buf = StringBuffer();

    buf.writeln("import 'dart:io';");
    buf.writeln();
    buf.writeln("import 'package:path/path.dart' as p;");
    buf.writeln("import 'package:path_provider/path_provider.dart';");
    buf.writeln("import 'package:sqflite_common_ffi/sqflite_ffi.dart';");
    buf.writeln();
    buf.writeln('class DatabaseHelper {');
    buf.writeln('  static final DatabaseHelper instance = DatabaseHelper._();');
    buf.writeln('  static Database? _db;');
    buf.writeln();
    buf.writeln('  DatabaseHelper._();');
    buf.writeln();
    buf.writeln('  Future<Database> get database async {');
    buf.writeln('    if (_db != null) return _db!;');
    buf.writeln('    _db = await _initDb();');
    buf.writeln('    return _db!;');
    buf.writeln('  }');
    buf.writeln();
    buf.writeln('  Future<Database> _initDb() async {');
    buf.writeln('    final dir = await getApplicationDocumentsDirectory();');
    buf.writeln("    final path = p.join(dir.path, '$packageName.db');");
    buf.writeln('    return await openDatabase(');
    buf.writeln('      path,');
    buf.writeln('      version: 1,');
    buf.writeln('      onCreate: (db, version) async {');

    // Create tables for all local data sources
    final localTables = <String, OdsDataSource>{};
    for (final entry in app.dataSources.entries) {
      final ds = entry.value;
      if (ds.isLocal) {
        localTables[ds.tableName] = ds;
      }
    }

    // Deduplicate by table name
    final seenTables = <String>{};
    for (final entry in localTables.entries) {
      final ds = entry.value;
      if (seenTables.contains(ds.tableName)) continue;
      seenTables.add(ds.tableName);

      // Collect columns from fields or from forms that submit to this data source
      final columns = _collectColumns(entry.key, ds, app);
      if (columns.isNotEmpty) {
        buf.writeln("        await db.execute('''");
        buf.writeln("          CREATE TABLE IF NOT EXISTS ${ds.tableName} (");
        buf.writeln("            _id TEXT PRIMARY KEY,");
        for (var i = 0; i < columns.length; i++) {
          final comma = i < columns.length - 1 ? ',' : '';
          buf.writeln("            ${columns[i]} TEXT$comma");
        }
        buf.writeln("          )");
        buf.writeln("        ''');");
      }

      // Seed data
      if (ds.seedData != null && ds.seedData!.isNotEmpty) {
        for (final row in ds.seedData!) {
          final keys = row.keys.toList();
          final colNames = keys.join(', ');
          final placeholders = keys.map((_) => '?').join(', ');
          final values = keys.map((k) => _dartString(row[k]?.toString() ?? '')).join(', ');
          buf.writeln("        await db.rawInsert(");
          buf.writeln("          'INSERT INTO ${ds.tableName} ($colNames) VALUES ($placeholders)',");
          buf.writeln("          [$values],");
          buf.writeln("        );");
        }
      }
    }

    buf.writeln('      },');
    buf.writeln('    );');
    buf.writeln('  }');
    buf.writeln();

    // CRUD methods
    buf.writeln('  Future<List<Map<String, dynamic>>> getAll(String table) async {');
    buf.writeln('    final db = await database;');
    buf.writeln('    return db.query(table);');
    buf.writeln('  }');
    buf.writeln();
    buf.writeln('  Future<int> insert(String table, Map<String, dynamic> data) async {');
    buf.writeln('    final db = await database;');
    buf.writeln('    return db.insert(table, data);');
    buf.writeln('  }');
    buf.writeln();
    buf.writeln('  Future<int> update(String table, Map<String, dynamic> data, String matchField, String matchValue) async {');
    buf.writeln('    final db = await database;');
    buf.writeln("    return db.update(table, data, where: '\$matchField = ?', whereArgs: [matchValue]);");
    buf.writeln('  }');
    buf.writeln();
    buf.writeln('  Future<int> delete(String table, String matchField, String matchValue) async {');
    buf.writeln('    final db = await database;');
    buf.writeln("    return db.delete(table, where: '\$matchField = ?', whereArgs: [matchValue]);");
    buf.writeln('  }');
    buf.writeln('}');

    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // Page widgets
  // ---------------------------------------------------------------------------

  String _genPage(
    String pageId,
    OdsPage page,
    OdsApp app,
    String packageName,
  ) {
    final className = _toClassName(pageId);
    final buf = StringBuffer();

    // Analyze what this page needs
    final hasForm = page.content.any((c) => c is OdsFormComponent);
    final hasList = page.content.any((c) => c is OdsListComponent);
    final hasChart = page.content.any((c) => c is OdsChartComponent);

    // Collect computed field info from all forms on this page
    final allComputedFields = <OdsFieldDefinition>[];
    final allNonComputedFields = <OdsFieldDefinition>[];
    for (final component in page.content) {
      if (component is OdsFormComponent) {
        for (final field in component.fields) {
          if (field.isComputed) {
            allComputedFields.add(field);
          } else {
            allNonComputedFields.add(field);
          }
        }
      }
    }
    final hasComputedFormFields = allComputedFields.isNotEmpty;

    // Collect computed field definitions for list columns (from data source fields + forms)
    final listComputedFields = <String, OdsFieldDefinition>{};
    for (final component in page.content) {
      if (component is OdsListComponent) {
        final ds = app.dataSources[component.dataSource];
        if (ds?.fields != null) {
          for (final field in ds!.fields!) {
            if (field.isComputed) listComputedFields[field.name] = field;
          }
        }
        // Also check forms that submit to this data source
        for (final p in app.pages.values) {
          for (final comp in p.content) {
            if (comp is OdsButtonComponent) {
              for (final action in comp.onClick) {
                if (action.isSubmit && action.dataSource == component.dataSource) {
                  for (final pp in app.pages.values) {
                    for (final cc in pp.content) {
                      if (cc is OdsFormComponent && cc.id == action.target) {
                        for (final f in cc.fields) {
                          if (f.isComputed) listComputedFields[f.name] = f;
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    final hasComputedListColumns = listComputedFields.isNotEmpty;
    final needsFormulaEvaluator = hasComputedFormFields || hasComputedListColumns;

    final hasMenu = app.menu.isNotEmpty;
    final hasHelp = app.help != null;
    final hasPageHelp = hasHelp && app.help!.pages.containsKey(pageId);
    final hasTour = app.tour.isNotEmpty;
    final hasAppSettings = app.settings.isNotEmpty;
    final needsAppSettings = hasAppSettings || hasTour;

    // Imports
    buf.writeln("import 'dart:io';");
    buf.writeln("import 'package:flutter/material.dart';");
    if (hasChart) {
      buf.writeln("import 'package:fl_chart/fl_chart.dart';");
      buf.writeln("import 'dart:math' as math;");
    }
    if (needsFormulaEvaluator) {
      buf.writeln("import '../data/formula_evaluator.dart';");
    }
    if (needsAppSettings) {
      buf.writeln("import '../data/app_settings.dart';");
    }
    buf.writeln("import '../data/database_helper.dart';");
    if (hasHelp) {
      buf.writeln("import '../screens/help_page.dart';");
    }
    if (hasTour) {
      buf.writeln("import '../screens/tour_dialog.dart';");
    }
    if (hasAppSettings) {
      buf.writeln("import '../screens/settings_dialog.dart';");
    }
    buf.writeln();

    // Widget class
    buf.writeln('class $className extends StatefulWidget {');
    buf.writeln('  const $className({super.key});');
    buf.writeln();
    buf.writeln('  @override');
    buf.writeln('  State<$className> createState() => _${className}State();');
    buf.writeln('}');
    buf.writeln();

    buf.writeln('class _${className}State extends State<$className> {');
    buf.writeln('  final _db = DatabaseHelper.instance;');

    // Form controllers
    for (final component in page.content) {
      if (component is OdsFormComponent) {
        for (final field in component.fields) {
          if (field.isComputed) continue;
          final controllerName = '_${field.name}Controller';
          buf.writeln('  final $controllerName = TextEditingController();');
        }
        buf.writeln('  final _formKey = GlobalKey<FormState>();');
      }
    }

    // Computed values map (live-updated by _updateComputed)
    if (hasComputedFormFields) {
      buf.writeln('  final Map<String, String> _computed = {};');
    }

    // List data state
    if (hasList || hasChart) {
      buf.writeln('  List<Map<String, dynamic>> _rows = [];');
      buf.writeln('  bool _loading = true;');
    }

    buf.writeln();

    // Unified initState
    final hasDefaults = page.content
        .whereType<OdsFormComponent>()
        .any((f) => f.fields.any((field) => field.defaultValue != null && !field.isComputed));
    final needsInitState = hasList || hasChart || hasDefaults || hasComputedFormFields || hasTour;
    if (needsInitState) {
      buf.writeln('  @override');
      buf.writeln('  void initState() {');
      buf.writeln('    super.initState();');
      if (hasList || hasChart) {
        buf.writeln('    _loadData();');
      }
      for (final component in page.content) {
        if (component is OdsFormComponent) {
          for (final field in component.fields) {
            if (field.isComputed) continue;
            if (field.defaultValue != null) {
              final controllerName = '_${field.name}Controller';
              if (field.defaultValue == 'NOW' || field.defaultValue == 'CURRENTDATE') {
                buf.writeln("    $controllerName.text = DateTime.now().toIso8601String().split('T')[0];");
              } else {
                buf.writeln("    $controllerName.text = ${_dartString(field.defaultValue!)};");
              }
            }
          }
        }
      }
      if (hasComputedFormFields) {
        buf.writeln('    _updateComputed();');
      }
      if (hasTour) {
        buf.writeln('    WidgetsBinding.instance.addPostFrameCallback((_) => _showTourIfNeeded());');
      }
      buf.writeln('  }');
      buf.writeln();
    }

    // _updateComputed — recalculates all formula-driven fields when sources change
    if (hasComputedFormFields) {
      buf.writeln('  void _updateComputed() {');
      buf.writeln('    if (!mounted) return;');
      buf.writeln('    final values = <String, String?>{');
      for (final f in allNonComputedFields) {
        buf.writeln("      '${f.name}': _${f.name}Controller.text,");
      }
      buf.writeln('    };');
      buf.writeln('    setState(() {');
      for (final field in allComputedFields) {
        buf.writeln("      _computed['${field.name}'] = FormulaEvaluator.evaluate(${_dartString(field.formula!)}, ${_dartString(field.type)}, values);");
      }
      buf.writeln('    });');
      buf.writeln('  }');
      buf.writeln();
    }

    // _showTourIfNeeded — shows guided tour on first launch
    if (hasTour) {
      buf.writeln('  Future<void> _showTourIfNeeded() async {');
      buf.writeln('    if (!mounted) return;');
      buf.writeln('    if (!AppSettings.instance.hasSeenTour()) {');
      buf.writeln('      await AppSettings.instance.markTourSeen();');
      buf.writeln('      if (mounted) AppTourDialog.show(context);');
      buf.writeln('    }');
      buf.writeln('  }');
      buf.writeln();
    }

    // _loadData for list/chart pages
    if (hasList || hasChart) {
      String? tableName;
      for (final c in page.content) {
        if (c is OdsListComponent) {
          final ds = app.dataSources[c.dataSource];
          if (ds != null && ds.isLocal) tableName = ds.tableName;
          break;
        }
        if (c is OdsChartComponent) {
          final ds = app.dataSources[c.dataSource];
          if (ds != null && ds.isLocal) tableName = ds.tableName;
          break;
        }
      }
      buf.writeln('  Future<void> _loadData() async {');
      if (tableName != null) {
        buf.writeln("    final data = await _db.getAll('$tableName');");
      } else {
        buf.writeln('    final data = <Map<String, dynamic>>[];');
      }
      buf.writeln('    setState(() {');
      buf.writeln('      _rows = data;');
      buf.writeln('      _loading = false;');
      buf.writeln('    });');
      buf.writeln('  }');
      buf.writeln();
    }

    // dispose controllers
    if (hasForm) {
      buf.writeln('  @override');
      buf.writeln('  void dispose() {');
      for (final component in page.content) {
        if (component is OdsFormComponent) {
          for (final field in component.fields) {
            if (field.isComputed) continue;
            buf.writeln('    _${field.name}Controller.dispose();');
          }
        }
      }
      buf.writeln('    super.dispose();');
      buf.writeln('  }');
      buf.writeln();
    }

    // build method
    buf.writeln('  @override');
    buf.writeln('  Widget build(BuildContext context) {');
    buf.writeln('    return Scaffold(');

    // AppBar — with optional help and tour action buttons
    buf.writeln('      appBar: AppBar(');
    buf.writeln("        title: Text(${_dartString(page.title)}),");
    if (hasHelp || hasTour) {
      buf.writeln('        actions: [');
      if (hasTour) {
        buf.writeln('          IconButton(');
        buf.writeln('            icon: const Icon(Icons.tour_outlined),');
        buf.writeln("            tooltip: 'Replay Tour',");
        buf.writeln('            onPressed: () => AppTourDialog.show(context),');
        buf.writeln('          ),');
      }
      if (hasHelp) {
        buf.writeln('          IconButton(');
        buf.writeln('            icon: const Icon(Icons.help_outline),');
        buf.writeln("            tooltip: 'Help',");
        buf.writeln('            onPressed: () => Navigator.push(context,');
        buf.writeln('              MaterialPageRoute(builder: (_) => const HelpPage())),');
        buf.writeln('          ),');
      }
      buf.writeln('        ],');
    }
    buf.writeln('      ),');

    // Drawer — navigation + settings + close app
    if (hasMenu) {
      buf.writeln('      drawer: Drawer(');
      buf.writeln('        child: ListView(');
      buf.writeln('          padding: EdgeInsets.zero,');
      buf.writeln('          children: [');
      buf.writeln('            DrawerHeader(');
      buf.writeln("              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),");
      buf.writeln("              child: Text(${_dartString(app.appName)}, style: const TextStyle(color: Colors.white, fontSize: 20)),");
      buf.writeln('            ),');
      for (final menuItem in app.menu) {
        buf.writeln('            ListTile(');
        buf.writeln("              title: Text(${_dartString(menuItem.label)}),");
        buf.writeln('              onTap: () {');
        buf.writeln('                Navigator.pop(context);');
        buf.writeln("                Navigator.pushReplacementNamed(context, ${_dartString(menuItem.mapsTo)});");
        buf.writeln('              },');
        buf.writeln('            ),');
      }
      buf.writeln('            const Divider(),');
      // Settings tile
      buf.writeln('            ListTile(');
      buf.writeln('              leading: const Icon(Icons.settings_outlined),');
      buf.writeln("              title: const Text('Settings'),");
      buf.writeln('              onTap: () {');
      buf.writeln('                Navigator.pop(context);');
      if (hasAppSettings) {
        buf.writeln('                showDialog(context: context, builder: (_) => const SettingsDialog());');
      } else {
        buf.writeln('                showDialog(');
        buf.writeln('                  context: context,');
        buf.writeln("                  builder: (ctx) => AlertDialog(");
        buf.writeln("                    title: const Text('Settings'),");
        buf.writeln("                    content: const Text('No app settings defined in this spec.'),");
        buf.writeln("                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],");
        buf.writeln('                  ),');
        buf.writeln('                );');
      }
      buf.writeln('              },');
      buf.writeln('            ),');
      // Close App tile
      buf.writeln('            const Divider(),');
      buf.writeln('            ListTile(');
      buf.writeln('              leading: const Icon(Icons.close),');
      buf.writeln("              title: const Text('Close App'),");
      buf.writeln('              onTap: () {');
      buf.writeln('                Navigator.pop(context);');
      buf.writeln('                exit(0);');
      buf.writeln('              },');
      buf.writeln('            ),');
      buf.writeln('          ],');
      buf.writeln('        ),');
      buf.writeln('      ),');
    }

    // Build the list of components into a buffer first (used below)
    final bodyChildren = StringBuffer();
    for (final component in page.content) {
      switch (component) {
        case OdsFormComponent c:
          _genFormComponent(bodyChildren, c, app, hasComputed: hasComputedFormFields);
        case OdsListComponent c:
          _genListComponent(bodyChildren, c, app, listComputedFields: listComputedFields);
        default:
          _genComponent(bodyChildren, component, app, pageId);
      }
    }

    // Body — with optional per-page help banner
    if (hasPageHelp) {
      buf.writeln('      body: Column(');
      buf.writeln('        crossAxisAlignment: CrossAxisAlignment.stretch,');
      buf.writeln('        children: [');
      buf.writeln('          ColoredBox(');
      buf.writeln('            color: Theme.of(context).colorScheme.secondaryContainer,');
      buf.writeln('            child: Padding(');
      buf.writeln('              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),');
      buf.writeln('              child: Row(children: [');
      buf.writeln('                Icon(Icons.info_outline, size: 16,');
      buf.writeln('                  color: Theme.of(context).colorScheme.onSecondaryContainer),');
      buf.writeln('                const SizedBox(width: 8),');
      buf.writeln('                Expanded(child: Text(');
      buf.writeln("                  ${_dartString(app.help!.pages[pageId]!)},");
      buf.writeln('                  style: TextStyle(fontSize: 13,');
      buf.writeln('                    color: Theme.of(context).colorScheme.onSecondaryContainer),');
      buf.writeln('                )),');
      buf.writeln('              ]),');
      buf.writeln('            ),');
      buf.writeln('          ),');
      buf.writeln('          Expanded(child: ListView(');
      buf.writeln('            padding: const EdgeInsets.all(16),');
      buf.writeln('            children: [');
      buf.write(bodyChildren.toString());
      buf.writeln('            ],');
      buf.writeln('          )),');
      buf.writeln('        ],');
      buf.writeln('      ),');
    } else {
      buf.writeln('      body: ListView(');
      buf.writeln('        padding: const EdgeInsets.all(16),');
      buf.writeln('        children: [');
      buf.write(bodyChildren.toString());
      buf.writeln('        ],');
      buf.writeln('      ),');
    }

    buf.writeln('    );');
    buf.writeln('  }');
    buf.writeln('}');

    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // Component code generation
  // ---------------------------------------------------------------------------

  void _genComponent(
    StringBuffer buf,
    OdsComponent component,
    OdsApp app,
    String pageId,
  ) {
    switch (component) {
      case OdsTextComponent c:
        _genTextComponent(buf, c);
      case OdsFormComponent c:
        _genFormComponent(buf, c, app);
      case OdsListComponent c:
        _genListComponent(buf, c, app);
      case OdsButtonComponent c:
        _genButtonComponent(buf, c, app, pageId);
      case OdsChartComponent c:
        _genChartComponent(buf, c);
      case OdsSummaryComponent c:
        _genSummaryComponent(buf, c);
      case OdsTabsComponent c:
        _genTabsComponent(buf, c, app, pageId);
      case OdsDetailComponent c:
        _genDetailComponent(buf, c);
      case OdsKanbanComponent c:
        _genKanbanComponent(buf, c);
      case OdsUnknownComponent _:
        buf.writeln("          // Unknown component type — skipped");
    }
  }

  void _genTextComponent(StringBuffer buf, OdsTextComponent c) {
    final variant = c.styleHint.variant;
    final color = c.styleHint.color;
    final align = c.styleHint.align;
    String? style;
    switch (variant) {
      case 'heading':
        style = 'Theme.of(context).textTheme.headlineSmall';
      case 'subheading':
        style = 'Theme.of(context).textTheme.titleMedium';
      case 'caption':
        style = 'Theme.of(context).textTheme.bodySmall';
    }

    // Apply color hint.
    String? colorExpr;
    if (color != null) {
      switch (color) {
        case 'success' || 'green':
          colorExpr = 'const Color(0xFF16A34A)';
        case 'warning' || 'amber' || 'orange':
          colorExpr = 'const Color(0xFFD97706)';
        case 'error' || 'red':
          colorExpr = 'Theme.of(context).colorScheme.error';
        case 'info' || 'blue':
          colorExpr = 'const Color(0xFF2563EB)';
        case 'grey' || 'gray':
          colorExpr = 'const Color(0xFF6B7280)';
        case 'purple':
          colorExpr = 'const Color(0xFF9333EA)';
        case 'teal':
          colorExpr = 'const Color(0xFF0D9488)';
        case 'indigo':
          colorExpr = 'const Color(0xFF4F46E5)';
      }
    }

    String? textAlignExpr;
    if (align == 'center') {
      textAlignExpr = 'TextAlign.center';
    } else if (align == 'right') {
      textAlignExpr = 'TextAlign.right';
    }

    // Combine style + color.
    String? combinedStyle;
    if (style != null && colorExpr != null) {
      combinedStyle = '$style?.copyWith(color: $colorExpr)';
    } else if (style != null) {
      combinedStyle = style;
    } else if (colorExpr != null) {
      combinedStyle = 'TextStyle(color: $colorExpr)';
    }

    buf.writeln('          Padding(');
    buf.writeln('            padding: const EdgeInsets.symmetric(vertical: 8),');
    buf.writeln('            child: Text(');
    buf.writeln('              ${_dartString(c.content)},');
    if (combinedStyle != null) {
      buf.writeln('              style: $combinedStyle,');
    }
    if (textAlignExpr != null) {
      buf.writeln('              textAlign: $textAlignExpr,');
    }
    buf.writeln('            ),');
    buf.writeln('          ),');
  }

  void _genFormComponent(StringBuffer buf, OdsFormComponent c, OdsApp app, {bool hasComputed = false}) {
    buf.writeln('          Form(');
    buf.writeln('            key: _formKey,');
    buf.writeln('            child: Column(');
    buf.writeln('              children: [');

    for (final field in c.fields) {
      if (field.isComputed) {
        // Computed field — reads from _computed map, updated live by _updateComputed()
        buf.writeln('                // Computed field: ${field.name} (formula: ${field.formula ?? ''})');
        buf.writeln('                Padding(');
        buf.writeln('                  padding: const EdgeInsets.symmetric(vertical: 8),');
        buf.writeln('                  child: InputDecorator(');
        buf.writeln('                    decoration: InputDecoration(');
        buf.writeln("                      labelText: ${_dartString('${field.label ?? field.name} (computed)')},");
        buf.writeln('                      border: const OutlineInputBorder(),');
        buf.writeln('                      filled: true,');
        buf.writeln('                      suffixIcon: const Icon(Icons.functions, size: 20),');
        buf.writeln('                    ),');
        buf.writeln("                    child: Text(_computed['${field.name}'] ?? ''),");
        buf.writeln('                  ),');
        buf.writeln('                ),');
        continue;
      }

      final controllerName = '_${field.name}Controller';

      if (field.type == 'select' && field.options != null && field.options!.isNotEmpty) {
        _genSelectField(buf, field, controllerName, hasComputed: hasComputed);
      } else if (field.type == 'checkbox') {
        _genCheckboxField(buf, field, controllerName, hasComputed: hasComputed);
      } else if (field.type == 'date' || field.type == 'datetime') {
        _genDateField(buf, field, controllerName, hasComputed: hasComputed);
      } else if (field.type == 'multiline') {
        _genMultilineField(buf, field, controllerName, hasComputed: hasComputed);
      } else {
        _genTextField(buf, field, controllerName, hasComputed: hasComputed);
      }
    }

    buf.writeln('              ],');
    buf.writeln('            ),');
    buf.writeln('          ),');
  }

  void _genTextField(StringBuffer buf, OdsFieldDefinition field, String controllerName, {bool hasComputed = false}) {
    final isNumber = field.type == 'number';
    buf.writeln('                Padding(');
    buf.writeln('                  padding: const EdgeInsets.symmetric(vertical: 8),');
    buf.writeln('                  child: TextFormField(');
    buf.writeln('                    controller: $controllerName,');
    buf.writeln("                    decoration: InputDecoration(");
    buf.writeln("                      labelText: ${_dartString(field.label ?? field.name)},");
    buf.writeln("                      border: const OutlineInputBorder(),");
    if (field.placeholder != null) {
      buf.writeln("                      hintText: ${_dartString(field.placeholder!)},");
    }
    buf.writeln("                    ),");
    if (isNumber) {
      buf.writeln("                    keyboardType: TextInputType.number,");
    }
    if (field.type == 'email') {
      buf.writeln("                    keyboardType: TextInputType.emailAddress,");
    }
    // Validation
    if (field.required || field.validation != null) {
      buf.writeln('                    validator: (value) {');
      if (field.required) {
        buf.writeln("                      if (value == null || value.trim().isEmpty) return 'Required';");
      }
      if (field.validation != null) {
        final v = field.validation!;
        if (v.minLength != null) {
          buf.writeln("                      if (value != null && value.length < ${v.minLength}) return ${_dartString(v.message ?? 'Must be at least ${v.minLength} characters')};");
        }
        if (isNumber && v.min != null) {
          buf.writeln("                      if (value != null && (double.tryParse(value) ?? 0) < ${v.min}) return ${_dartString(v.message ?? 'Minimum value is ${v.min}')};");
        }
        if (isNumber && v.max != null) {
          buf.writeln("                      if (value != null && (double.tryParse(value) ?? 0) > ${v.max}) return ${_dartString(v.message ?? 'Maximum value is ${v.max}')};");
        }
      }
      buf.writeln("                      return null;");
      buf.writeln('                    },');
    }
    if (hasComputed) {
      buf.writeln('                    onChanged: (_) => _updateComputed(),');
    }
    buf.writeln('                  ),');
    buf.writeln('                ),');
  }

  void _genMultilineField(StringBuffer buf, OdsFieldDefinition field, String controllerName, {bool hasComputed = false}) {
    buf.writeln('                Padding(');
    buf.writeln('                  padding: const EdgeInsets.symmetric(vertical: 8),');
    buf.writeln('                  child: TextFormField(');
    buf.writeln('                    controller: $controllerName,');
    buf.writeln('                    maxLines: 4,');
    buf.writeln("                    decoration: InputDecoration(");
    buf.writeln("                      labelText: ${_dartString(field.label ?? field.name)},");
    buf.writeln("                      border: const OutlineInputBorder(),");
    buf.writeln("                      alignLabelWithHint: true,");
    buf.writeln("                    ),");
    if (hasComputed) {
      buf.writeln('                    onChanged: (_) => _updateComputed(),');
    }
    buf.writeln('                  ),');
    buf.writeln('                ),');
  }

  void _genSelectField(StringBuffer buf, OdsFieldDefinition field, String controllerName, {bool hasComputed = false}) {
    buf.writeln('                Padding(');
    buf.writeln('                  padding: const EdgeInsets.symmetric(vertical: 8),');
    buf.writeln('                  child: DropdownButtonFormField<String>(');
    buf.writeln("                    decoration: InputDecoration(");
    buf.writeln("                      labelText: ${_dartString(field.label ?? field.name)},");
    buf.writeln("                      border: const OutlineInputBorder(),");
    buf.writeln("                    ),");
    buf.writeln('                    value: $controllerName.text.isNotEmpty ? $controllerName.text : null,');
    buf.writeln('                    items: [');
    for (final opt in field.options!) {
      buf.writeln("                      DropdownMenuItem(value: ${_dartString(opt)}, child: Text(${_dartString(opt)})),");
    }
    buf.writeln('                    ],');
    buf.writeln('                    onChanged: (value) {');
    buf.writeln("                      setState(() { $controllerName.text = value ?? ''; });");
    if (hasComputed) {
      buf.writeln('                      _updateComputed();');
    }
    buf.writeln('                    },');
    buf.writeln('                  ),');
    buf.writeln('                ),');
  }

  void _genCheckboxField(StringBuffer buf, OdsFieldDefinition field, String controllerName, {bool hasComputed = false}) {
    buf.writeln('                Padding(');
    buf.writeln('                  padding: const EdgeInsets.symmetric(vertical: 8),');
    buf.writeln('                  child: CheckboxListTile(');
    buf.writeln("                    title: Text(${_dartString(field.label ?? field.name)}),");
    buf.writeln("                    value: $controllerName.text == 'true',");
    buf.writeln('                    onChanged: (value) {');
    buf.writeln("                      setState(() { $controllerName.text = (value ?? false).toString(); });");
    if (hasComputed) {
      buf.writeln('                      _updateComputed();');
    }
    buf.writeln('                    },');
    buf.writeln('                  ),');
    buf.writeln('                ),');
  }

  void _genDateField(StringBuffer buf, OdsFieldDefinition field, String controllerName, {bool hasComputed = false}) {
    final isDateTime = field.type == 'datetime';
    buf.writeln('                Padding(');
    buf.writeln('                  padding: const EdgeInsets.symmetric(vertical: 8),');
    buf.writeln('                  child: TextFormField(');
    buf.writeln('                    controller: $controllerName,');
    buf.writeln('                    readOnly: true,');
    buf.writeln("                    decoration: InputDecoration(");
    buf.writeln("                      labelText: ${_dartString(field.label ?? field.name)},");
    buf.writeln("                      border: const OutlineInputBorder(),");
    buf.writeln("                      suffixIcon: Icon(${isDateTime ? 'Icons.access_time' : 'Icons.calendar_today'}),");
    buf.writeln("                    ),");
    buf.writeln('                    onTap: () async {');
    buf.writeln('                      final date = await showDatePicker(');
    buf.writeln('                        context: context,');
    buf.writeln('                        initialDate: DateTime.now(),');
    buf.writeln('                        firstDate: DateTime(2000),');
    buf.writeln('                        lastDate: DateTime(2100),');
    buf.writeln('                      );');
    buf.writeln('                      if (date == null || !mounted) return;');
    if (isDateTime) {
      buf.writeln('                      final time = await showTimePicker(');
      buf.writeln('                        context: context,');
      buf.writeln('                        initialTime: TimeOfDay.now(),');
      buf.writeln('                      );');
      buf.writeln('                      if (time == null || !mounted) return;');
      buf.writeln("                      $controllerName.text = '\${date.year}-\${date.month.toString().padLeft(2, '0')}-\${date.day.toString().padLeft(2, '0')} \${time.hour.toString().padLeft(2, '0')}:\${time.minute.toString().padLeft(2, '0')}';");
    } else {
      buf.writeln("                      $controllerName.text = date.toIso8601String().split('T')[0];");
    }
    if (hasComputed) {
      buf.writeln('                      _updateComputed();');
    }
    buf.writeln('                    },');
    buf.writeln('                  ),');
    buf.writeln('                ),');
  }

  void _genListComponent(
    StringBuffer buf,
    OdsListComponent c,
    OdsApp app, {
    Map<String, OdsFieldDefinition> listComputedFields = const {},
  }) {
    // Identify which columns are computed (need formula evaluation per row)
    final computedColumns = c.columns.where((col) => listComputedFields.containsKey(col.field)).toList();
    final hasComputedCols = computedColumns.isNotEmpty;

    buf.writeln('          if (_loading)');
    buf.writeln('            const Center(child: CircularProgressIndicator())');
    buf.writeln('          else if (_rows.isEmpty)');
    buf.writeln("            const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No data yet.')))");
    buf.writeln('          else');
    buf.writeln('            SingleChildScrollView(');
    buf.writeln('              scrollDirection: Axis.horizontal,');
    buf.writeln('              child: DataTable(');
    buf.writeln('                columns: [');
    for (final col in c.columns) {
      buf.writeln("                  DataColumn(label: Text(${_dartString(col.header)})),");
    }
    buf.writeln('                ],');
    buf.writeln('                rows: _rows.map((row) {');
    // Pre-compute formula values for this row
    if (hasComputedCols) {
      buf.writeln('                  final rowStr = row.map((k, v) => MapEntry(k, v?.toString()));');
      for (final col in computedColumns) {
        final f = listComputedFields[col.field]!;
        buf.writeln("                  final _cv_${col.field} = FormulaEvaluator.evaluate(${_dartString(f.formula!)}, ${_dartString(f.type)}, rowStr);");
      }
    }
    buf.writeln('                  return DataRow(cells: [');
    for (final col in c.columns) {
      if (listComputedFields.containsKey(col.field)) {
        buf.writeln("                    DataCell(Text(_cv_${col.field})),");
      } else {
        buf.writeln("                    DataCell(Text(row[${_dartString(col.field)}]?.toString() ?? '')),");
      }
    }
    buf.writeln('                  ]);');
    buf.writeln('                }).toList(),');
    buf.writeln('              ),');
    buf.writeln('            ),');

    // Summary row
    if (c.summary.isNotEmpty) {
      buf.writeln('          if (!_loading && _rows.isNotEmpty)');
      buf.writeln('            Card(');
      buf.writeln('              color: Theme.of(context).colorScheme.surfaceContainerHighest,');
      buf.writeln('              child: Padding(');
      buf.writeln('                padding: const EdgeInsets.all(12),');
      buf.writeln('                child: Wrap(');
      buf.writeln('                  spacing: 24,');
      buf.writeln('                  children: [');
      for (final rule in c.summary) {
        final label = rule.label ?? '${rule.function} of ${rule.column}';
        final isComputedCol = listComputedFields.containsKey(rule.column);
        if (isComputedCol) {
          final f = listComputedFields[rule.column]!;
          // For computed columns, re-evaluate the formula per row for the aggregation
          final formulaStr = _dartString(f.formula!);
          final typeStr = _dartString(f.type);
          switch (rule.function) {
            case 'count':
              buf.writeln("                    Text('$label: \${_rows.length}', style: const TextStyle(fontWeight: FontWeight.w600)),");
            case 'sum':
              buf.writeln("                    Text('$label: \${_rows.fold<double>(0, (a, r) => a + (double.tryParse(FormulaEvaluator.evaluate($formulaStr, $typeStr, r.map((k, v) => MapEntry(k, v?.toString())))) ?? 0)).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),");
            case 'avg':
              buf.writeln("                    Text('$label: \${(_rows.fold<double>(0, (a, r) => a + (double.tryParse(FormulaEvaluator.evaluate($formulaStr, $typeStr, r.map((k, v) => MapEntry(k, v?.toString())))) ?? 0)) / _rows.length).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),");
            default:
              buf.writeln("                    Text('$label: -'),");
          }
        } else {
          switch (rule.function) {
            case 'count':
              buf.writeln("                    Text('$label: \${_rows.length}', style: const TextStyle(fontWeight: FontWeight.w600)),");
            case 'sum':
              buf.writeln("                    Text('$label: \${_rows.fold<double>(0, (a, r) => a + (double.tryParse(r[${_dartString(rule.column)}]?.toString() ?? '') ?? 0)).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),");
            case 'avg':
              buf.writeln("                    Text('$label: \${(_rows.fold<double>(0, (a, r) => a + (double.tryParse(r[${_dartString(rule.column)}]?.toString() ?? '') ?? 0)) / _rows.length).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),");
            default:
              buf.writeln("                    Text('$label: -'),");
          }
        }
      }
      buf.writeln('                  ],');
      buf.writeln('                ),');
      buf.writeln('              ),');
      buf.writeln('            ),');
    }
  }

  void _genButtonComponent(
    StringBuffer buf,
    OdsButtonComponent c,
    OdsApp app,
    String pageId,
  ) {
    final emphasis = c.styleHint.emphasis;
    final variant = c.styleHint.get<String>('variant') ?? 'filled';
    final iconName = c.styleHint.icon;
    final isDanger = emphasis == 'danger';
    // Choose widget type based on variant hint.
    final widgetType = switch (variant) {
      'outlined' => 'OutlinedButton',
      'text' => 'TextButton',
      _ => 'ElevatedButton',
    };

    buf.writeln('          Padding(');
    buf.writeln('            padding: const EdgeInsets.symmetric(vertical: 8),');
    buf.writeln('            child: $widgetType(');
    if (isDanger) {
      buf.writeln('              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),');
    }
    buf.writeln('              onPressed: () async {');

    // Generate action chain
    for (final action in c.onClick) {
      if (action.confirm != null) {
        buf.writeln("                final confirmed = await showDialog<bool>(");
        buf.writeln("                  context: context,");
        buf.writeln("                  builder: (ctx) => AlertDialog(");
        buf.writeln("                    title: const Text('Confirm'),");
        buf.writeln("                    content: Text(${_dartString(action.confirm!)}),");
        buf.writeln("                    actions: [");
        buf.writeln("                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),");
        buf.writeln("                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),");
        buf.writeln("                    ],");
        buf.writeln("                  ),");
        buf.writeln("                );");
        buf.writeln("                if (confirmed != true) return;");
      }

      if (action.isSubmit && action.target != null && action.dataSource != null) {
        final ds = app.dataSources[action.dataSource];
        final tableName = ds?.tableName ?? action.dataSource!;

        // Find the form
        OdsFormComponent? form;
        for (final p in app.pages.values) {
          for (final comp in p.content) {
            if (comp is OdsFormComponent && comp.id == action.target) {
              form = comp;
              break;
            }
          }
        }

        if (form != null) {
          buf.writeln('                if (_formKey.currentState?.validate() ?? false) {');
          buf.writeln("                  await _db.insert('$tableName', {");
          for (final field in form.fields) {
            if (field.isComputed) continue;
            buf.writeln("                    ${_dartString(field.name)}: _${field.name}Controller.text,");
          }
          buf.writeln('                  });');
          // Clear form
          for (final field in form.fields) {
            if (field.isComputed) continue;
            buf.writeln("                  _${field.name}Controller.clear();");
          }
          buf.writeln('                }');
        }
      }

      if (action.isNavigate && action.target != null) {
        buf.writeln("                if (mounted) Navigator.pushReplacementNamed(context, ${_dartString(action.target!)});");
      }
    }

    buf.writeln('              },');
    // Add icon if specified in styleHint.
    if (iconName != null) {
      final iconMap = const {
        'add': 'Icons.add', 'add_circle': 'Icons.add_circle_outline',
        'save': 'Icons.save_outlined', 'check': 'Icons.check',
        'check_circle': 'Icons.check_circle_outline', 'delete': 'Icons.delete_outline',
        'edit': 'Icons.edit_outlined', 'arrow_back': 'Icons.arrow_back',
        'close': 'Icons.close', 'search': 'Icons.search',
        'send': 'Icons.send_outlined', 'visibility': 'Icons.visibility_outlined',
        'rocket': 'Icons.rocket_launch_outlined', 'event': 'Icons.event_outlined',
        'cancel': 'Icons.cancel_outlined', 'star': 'Icons.star_outline',
      };
      final iconExpr = iconMap[iconName] ?? 'Icons.circle_outlined';
      buf.writeln("              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon($iconExpr, size: 18), const SizedBox(width: 8), Text(${_dartString(c.label)})]),");
    } else {
      buf.writeln("              child: Text(${_dartString(c.label)}),");
    }
    buf.writeln('            ),');
    buf.writeln('          ),');
  }

  void _genChartComponent(StringBuffer buf, OdsChartComponent c) {
    final labelField = _dartString(c.labelField);
    final valueField = _dartString(c.valueField);

    buf.writeln('          if (!_loading && _rows.isNotEmpty)');
    buf.writeln('            Card(');
    buf.writeln('              child: Padding(');
    buf.writeln('                padding: const EdgeInsets.all(16),');
    buf.writeln('                child: Column(');
    buf.writeln('                  children: [');
    if (c.title != null) {
      buf.writeln("                    Text(${_dartString(c.title!)}, style: Theme.of(context).textTheme.titleMedium),");
      buf.writeln('                    const SizedBox(height: 12),');
    }
    buf.writeln('                    SizedBox(');
    buf.writeln('                      height: 250,');
    buf.writeln('                      child: Builder(builder: (context) {');
    buf.writeln('                        // Aggregate rows by label field, summing value field');
    buf.writeln('                        final aggregated = <String, double>{};');
    buf.writeln('                        for (final row in _rows) {');
    buf.writeln('                          final label = (row[$labelField] ?? "Other").toString();');
    buf.writeln('                          final value = double.tryParse((row[$valueField] ?? "0").toString()) ?? 0;');
    buf.writeln('                          aggregated[label] = (aggregated[label] ?? 0) + value;');
    buf.writeln('                        }');
    buf.writeln('                        final entries = aggregated.entries.toList();');
    buf.writeln('                        final colors = [');
    buf.writeln('                          Colors.blue, Colors.red, Colors.green, Colors.orange,');
    buf.writeln('                          Colors.purple, Colors.teal, Colors.pink, Colors.amber,');
    buf.writeln('                        ];');

    switch (c.chartType) {
      case 'pie':
        buf.writeln('                        return PieChart(');
        buf.writeln('                          PieChartData(');
        buf.writeln('                            sections: entries.asMap().entries.map((e) {');
        buf.writeln('                              final color = colors[e.key % colors.length];');
        buf.writeln('                              return PieChartSectionData(');
        buf.writeln('                                value: e.value.value,');
        buf.writeln('                                title: e.value.key,');
        buf.writeln('                                color: color,');
        buf.writeln('                                radius: 80,');
        buf.writeln('                                titleStyle: const TextStyle(fontSize: 12, color: Colors.white),');
        buf.writeln('                              );');
        buf.writeln('                            }).toList(),');
        buf.writeln('                          ),');
        buf.writeln('                        );');
      case 'line':
        buf.writeln('                        return LineChart(');
        buf.writeln('                          LineChartData(');
        buf.writeln('                            lineBarsData: [');
        buf.writeln('                              LineChartBarData(');
        buf.writeln('                                spots: entries.asMap().entries.map((e) {');
        buf.writeln('                                  return FlSpot(e.key.toDouble(), e.value.value);');
        buf.writeln('                                }).toList(),');
        buf.writeln('                                isCurved: true,');
        buf.writeln('                                color: Colors.blue,');
        buf.writeln('                              ),');
        buf.writeln('                            ],');
        buf.writeln('                            titlesData: FlTitlesData(');
        buf.writeln('                              bottomTitles: AxisTitles(');
        buf.writeln('                                sideTitles: SideTitles(');
        buf.writeln('                                  showTitles: true,');
        buf.writeln('                                  getTitlesWidget: (value, meta) {');
        buf.writeln('                                    final idx = value.toInt();');
        buf.writeln('                                    if (idx >= 0 && idx < entries.length) {');
        buf.writeln('                                      return Text(entries[idx].key, style: const TextStyle(fontSize: 10));');
        buf.writeln('                                    }');
        buf.writeln('                                    return const SizedBox.shrink();');
        buf.writeln('                                  },');
        buf.writeln('                                ),');
        buf.writeln('                              ),');
        buf.writeln('                            ),');
        buf.writeln('                          ),');
        buf.writeln('                        );');
      default: // bar
        buf.writeln('                        return BarChart(');
        buf.writeln('                          BarChartData(');
        buf.writeln('                            barGroups: entries.asMap().entries.map((e) {');
        buf.writeln('                              return BarChartGroupData(');
        buf.writeln('                                x: e.key,');
        buf.writeln('                                barRods: [');
        buf.writeln('                                  BarChartRodData(');
        buf.writeln('                                    toY: e.value.value,');
        buf.writeln('                                    color: colors[e.key % colors.length],');
        buf.writeln('                                  ),');
        buf.writeln('                                ],');
        buf.writeln('                              );');
        buf.writeln('                            }).toList(),');
        buf.writeln('                            titlesData: FlTitlesData(');
        buf.writeln('                              bottomTitles: AxisTitles(');
        buf.writeln('                                sideTitles: SideTitles(');
        buf.writeln('                                  showTitles: true,');
        buf.writeln('                                  getTitlesWidget: (value, meta) {');
        buf.writeln('                                    final idx = value.toInt();');
        buf.writeln('                                    if (idx >= 0 && idx < entries.length) {');
        buf.writeln('                                      return Text(entries[idx].key, style: const TextStyle(fontSize: 10));');
        buf.writeln('                                    }');
        buf.writeln('                                    return const SizedBox.shrink();');
        buf.writeln('                                  },');
        buf.writeln('                                ),');
        buf.writeln('                              ),');
        buf.writeln('                            ),');
        buf.writeln('                          ),');
        buf.writeln('                        );');
    }

    buf.writeln('                      }),');
    buf.writeln('                    ),');
    buf.writeln('                  ],');
    buf.writeln('                ),');
    buf.writeln('              ),');
    buf.writeln('            ),');
  }

  // ---------------------------------------------------------------------------
  // Summary component
  // ---------------------------------------------------------------------------

  void _genSummaryComponent(StringBuffer buf, OdsSummaryComponent c) {
    final label = _dartString(c.label);
    final value = _dartString(c.value);

    // Map common icon names to Flutter Icons constants.
    String iconExpr = 'Icons.info_outline';
    if (c.icon != null) {
      iconExpr = 'Icons.${c.icon}';
    }

    buf.writeln('          Card(');
    buf.writeln('            child: Padding(');
    buf.writeln('              padding: const EdgeInsets.all(16),');
    buf.writeln('              child: Row(');
    buf.writeln('                children: [');
    if (c.icon != null) {
      buf.writeln('                  Icon($iconExpr, size: 36, color: Theme.of(context).colorScheme.primary),');
      buf.writeln('                  const SizedBox(width: 16),');
    }
    buf.writeln('                  Expanded(');
    buf.writeln('                    child: Column(');
    buf.writeln('                      crossAxisAlignment: CrossAxisAlignment.start,');
    buf.writeln('                      children: [');
    buf.writeln('                        Text($label, style: Theme.of(context).textTheme.bodySmall),');
    buf.writeln('                        const SizedBox(height: 4),');
    buf.writeln('                        Text(');
    buf.writeln('                          $value, // TODO: Replace with computed aggregate value');
    buf.writeln('                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),');
    buf.writeln('                        ),');
    buf.writeln('                      ],');
    buf.writeln('                    ),');
    buf.writeln('                  ),');
    buf.writeln('                ],');
    buf.writeln('              ),');
    buf.writeln('            ),');
    buf.writeln('          ),');
  }

  // ---------------------------------------------------------------------------
  // Tabs component
  // ---------------------------------------------------------------------------

  void _genTabsComponent(StringBuffer buf, OdsTabsComponent c, OdsApp app, String pageId) {
    final tabCount = c.tabs.length;

    buf.writeln('          DefaultTabController(');
    buf.writeln('            length: $tabCount,');
    buf.writeln('            child: Column(');
    buf.writeln('              mainAxisSize: MainAxisSize.min,');
    buf.writeln('              children: [');
    buf.writeln('                TabBar(');
    buf.writeln('                  isScrollable: $tabCount > 4,');
    buf.writeln('                  tabs: [');
    for (final tab in c.tabs) {
      buf.writeln('                    Tab(text: ${_dartString(tab.label)}),');
    }
    buf.writeln('                  ],');
    buf.writeln('                ),');
    buf.writeln('                SizedBox(');
    buf.writeln('                  height: 400, // Adjust height as needed');
    buf.writeln('                  child: TabBarView(');
    buf.writeln('                    children: [');
    for (final tab in c.tabs) {
      buf.writeln('                      SingleChildScrollView(');
      buf.writeln('                        padding: const EdgeInsets.all(16),');
      buf.writeln('                        child: Column(');
      buf.writeln('                          crossAxisAlignment: CrossAxisAlignment.stretch,');
      buf.writeln('                          children: [');
      for (final child in tab.content) {
        _genComponent(buf, child, app, pageId);
      }
      buf.writeln('                          ],');
      buf.writeln('                        ),');
      buf.writeln('                      ),');
    }
    buf.writeln('                    ],');
    buf.writeln('                  ),');
    buf.writeln('                ),');
    buf.writeln('              ],');
    buf.writeln('            ),');
    buf.writeln('          ),');
  }

  // ---------------------------------------------------------------------------
  // Detail component
  // ---------------------------------------------------------------------------

  void _genDetailComponent(StringBuffer buf, OdsDetailComponent c) {
    final fields = c.fields ?? [];
    final labels = c.labels ?? {};
    final source = c.fromForm != null
        ? 'form "${c.fromForm}"'
        : 'dataSource "${c.dataSource}"';

    buf.writeln('          // Detail view — data loaded from $source');
    buf.writeln('          Card(');
    buf.writeln('            child: Padding(');
    buf.writeln('              padding: const EdgeInsets.all(16),');
    buf.writeln('              child: Column(');
    buf.writeln('                crossAxisAlignment: CrossAxisAlignment.start,');
    buf.writeln('                children: [');

    if (fields.isEmpty) {
      buf.writeln('                  // No explicit fields — display all record fields');
      buf.writeln("                  // TODO: Iterate over your record's keys and display each one");
      buf.writeln('                  const Text(');
      buf.writeln("                    'No fields specified — wire up record display here.',");
      buf.writeln('                    style: TextStyle(fontStyle: FontStyle.italic),');
      buf.writeln('                  ),');
    } else {
      for (final field in fields) {
        final displayLabel = labels[field] ?? _toDisplayLabel(field);
        buf.writeln('                  Padding(');
        buf.writeln('                    padding: const EdgeInsets.symmetric(vertical: 6),');
        buf.writeln('                    child: Row(');
        buf.writeln('                      crossAxisAlignment: CrossAxisAlignment.start,');
        buf.writeln('                      children: [');
        buf.writeln('                        SizedBox(');
        buf.writeln('                          width: 140,');
        buf.writeln('                          child: Text(');
        buf.writeln('                            ${_dartString(displayLabel)},');
        buf.writeln('                            style: const TextStyle(fontWeight: FontWeight.bold),');
        buf.writeln('                          ),');
        buf.writeln('                        ),');
        buf.writeln('                        Expanded(');
        buf.writeln('                          child: Text(');
        buf.writeln("                            _record[${_dartString(field)}]?.toString() ?? '',");
        buf.writeln('                          ),');
        buf.writeln('                        ),');
        buf.writeln('                      ],');
        buf.writeln('                    ),');
        buf.writeln('                  ),');
      }
    }

    buf.writeln('                ],');
    buf.writeln('              ),');
    buf.writeln('            ),');
    buf.writeln('          ),');
  }

  // ---------------------------------------------------------------------------
  // Kanban component
  // ---------------------------------------------------------------------------

  void _genKanbanComponent(StringBuffer buf, OdsKanbanComponent c) {
    final statusField = _dartString(c.statusField);
    final titleField = c.titleField != null ? _dartString(c.titleField!) : _dartString(c.cardFields.isNotEmpty ? c.cardFields.first : 'title');
    final dataSource = c.dataSource;

    buf.writeln('          // Kanban board — dataSource: "$dataSource", statusField: ${c.statusField}');
    buf.writeln('          // Each column represents a status value; cards are rows from the data source.');
    buf.writeln('          // TODO: Load status options from the data source field definition');
    buf.writeln('          // TODO: Implement drag-and-drop to update ${c.statusField} on drop');
    buf.writeln('          SizedBox(');
    buf.writeln('            height: 500,');
    buf.writeln('            child: Builder(builder: (context) {');
    buf.writeln('              // Group rows by status field');
    buf.writeln('              final columns = <String, List<Map<String, dynamic>>>{};');
    buf.writeln('              for (final row in _rows) {');
    buf.writeln('                final status = (row[$statusField] ?? "Unknown").toString();');
    buf.writeln('                columns.putIfAbsent(status, () => []).add(row);');
    buf.writeln('              }');
    buf.writeln('              final statuses = columns.keys.toList();');
    buf.writeln('              return ListView.builder(');
    buf.writeln('                scrollDirection: Axis.horizontal,');
    buf.writeln('                itemCount: statuses.length,');
    buf.writeln('                itemBuilder: (context, colIndex) {');
    buf.writeln('                  final status = statuses[colIndex];');
    buf.writeln('                  final cards = columns[status]!;');
    buf.writeln('                  return SizedBox(');
    buf.writeln('                    width: 280,');
    buf.writeln('                    child: Card(');
    buf.writeln('                      child: Column(');
    buf.writeln('                        children: [');
    buf.writeln('                          // Column header');
    buf.writeln('                          Container(');
    buf.writeln('                            width: double.infinity,');
    buf.writeln('                            padding: const EdgeInsets.all(12),');
    buf.writeln('                            color: Theme.of(context).colorScheme.primaryContainer,');
    buf.writeln("                            child: Text(");
    buf.writeln("                              '\$status (\${cards.length})',");
    buf.writeln("                              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),");
    buf.writeln('                            ),');
    buf.writeln('                          ),');
    buf.writeln('                          // Cards in this column');
    buf.writeln('                          Expanded(');
    buf.writeln('                            child: ListView.builder(');
    buf.writeln('                              padding: const EdgeInsets.all(8),');
    buf.writeln('                              itemCount: cards.length,');
    buf.writeln('                              itemBuilder: (context, cardIndex) {');
    buf.writeln('                                final row = cards[cardIndex];');
    buf.writeln('                                return Card(');
    buf.writeln('                                  elevation: 2,');
    buf.writeln('                                  margin: const EdgeInsets.only(bottom: 8),');
    buf.writeln('                                  child: Padding(');
    buf.writeln('                                    padding: const EdgeInsets.all(12),');
    buf.writeln('                                    child: Column(');
    buf.writeln('                                      crossAxisAlignment: CrossAxisAlignment.start,');
    buf.writeln('                                      children: [');
    buf.writeln('                                        Text(');
    buf.writeln("                                          (row[$titleField] ?? '').toString(),");
    buf.writeln('                                          style: const TextStyle(fontWeight: FontWeight.bold),');
    buf.writeln('                                        ),');

    // Add additional card fields
    for (final field in c.cardFields) {
      if (field == c.titleField) continue; // Skip the title field, already shown
      final fieldStr = _dartString(field);
      buf.writeln('                                        const SizedBox(height: 4),');
      buf.writeln('                                        Text(');
      buf.writeln("                                          (row[$fieldStr] ?? '').toString(),");
      buf.writeln('                                          style: Theme.of(context).textTheme.bodySmall,');
      buf.writeln('                                        ),');
    }

    buf.writeln('                                      ],');
    buf.writeln('                                    ),');
    buf.writeln('                                  ),');
    buf.writeln('                                );');
    buf.writeln('                              },');
    buf.writeln('                            ),');
    buf.writeln('                          ),');
    buf.writeln('                        ],');
    buf.writeln('                      ),');
    buf.writeln('                    ),');
    buf.writeln('                  );');
    buf.writeln('                },');
    buf.writeln('              );');
    buf.writeln('            }),');
    buf.writeln('          ),');
  }

  /// Converts a camelCase or snake_case field name to a human-readable label.
  String _toDisplayLabel(String fieldName) {
    // Insert space before uppercase letters (camelCase → camel Case)
    final spaced = fieldName.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    // Replace underscores with spaces
    final cleaned = spaced.replaceAll('_', ' ');
    // Capitalize first letter
    if (cleaned.isEmpty) return cleaned;
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }

  // ---------------------------------------------------------------------------
  // New helper file generators
  // ---------------------------------------------------------------------------

  String _genFormulaEvaluator() {
    return r'''
/// Evaluates formula expressions for computed fields.
///
/// Computed fields use `{fieldName}` placeholders to reference other fields.
/// For number-type fields, the result is evaluated as a math expression
/// (supports +, -, *, /, parentheses). For text-type fields, placeholders
/// are simply replaced with their values (string interpolation).
class FormulaEvaluator {
  static final _fieldPattern = RegExp(r'\{(\w+)\}');

  /// Returns the list of field names referenced in a formula.
  static List<String> dependencies(String formula) {
    return _fieldPattern
        .allMatches(formula)
        .map((m) => m.group(1)!)
        .toSet()
        .toList();
  }

  /// Evaluates a formula given field values.
  static String evaluate(
    String formula,
    String fieldType,
    Map<String, String?> values,
  ) {
    // Check that all referenced fields have values.
    for (final match in _fieldPattern.allMatches(formula)) {
      final name = match.group(1)!;
      final val = values[name];
      if (val == null || val.isEmpty) return '';
    }

    // Substitute field references with their values.
    final substituted = formula.replaceAllMapped(_fieldPattern, (match) {
      return values[match.group(1)!] ?? '';
    });

    if (fieldType == 'number') {
      try {
        final result = _evaluateMath(substituted);
        if (result == result.roundToDouble()) {
          return result.toInt().toString();
        }
        return result.toStringAsFixed(2);
      } catch (_) {
        return '';
      }
    }

    return substituted;
  }

  static double _evaluateMath(String expression) {
    final tokens = _tokenize(expression);
    final parser = _MathParser(tokens);
    final result = parser.parseExpression();
    if (parser.pos < tokens.length) {
      throw FormatException('Unexpected token: ${tokens[parser.pos]}');
    }
    return result;
  }

  static List<String> _tokenize(String expr) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    for (var i = 0; i < expr.length; i++) {
      final ch = expr[i];
      if (ch == ' ') {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }
      if ('+-*/()'.contains(ch)) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        if (ch == '-' &&
            (tokens.isEmpty || tokens.last == '(' || '+-*/'.contains(tokens.last))) {
          buffer.write('-');
        } else {
          tokens.add(ch);
        }
      } else {
        buffer.write(ch);
      }
    }
    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
    }
    return tokens;
  }
}

class _MathParser {
  final List<String> _tokens;
  int pos = 0;

  _MathParser(this._tokens);

  String? _peek() => pos < _tokens.length ? _tokens[pos] : null;

  String _consume() {
    if (pos >= _tokens.length) throw FormatException('Unexpected end of expression');
    return _tokens[pos++];
  }

  double parseExpression() {
    var result = _parseTerm();
    while (_peek() == '+' || _peek() == '-') {
      final op = _consume();
      final right = _parseTerm();
      result = op == '+' ? result + right : result - right;
    }
    return result;
  }

  double _parseTerm() {
    var result = _parseFactor();
    while (_peek() == '*' || _peek() == '/') {
      final op = _consume();
      final right = _parseFactor();
      result = op == '*' ? result * right : result / right;
    }
    return result;
  }

  double _parseFactor() {
    if (_peek() == '(') {
      _consume();
      final result = parseExpression();
      if (_peek() != ')') throw FormatException('Expected closing parenthesis');
      _consume();
      return result;
    }
    final token = _consume();
    final value = double.tryParse(token);
    if (value == null) throw FormatException('Expected number, got: $token');
    return value;
  }
}
''';
  }

  String _genAppSettings(OdsApp app) {
    final buf = StringBuffer();
    buf.writeln("import 'package:flutter/material.dart';");
    buf.writeln("import 'package:shared_preferences/shared_preferences.dart';");
    buf.writeln();
    buf.writeln('/// Singleton that persists app settings and tour state via SharedPreferences.');
    buf.writeln('class AppSettings {');
    buf.writeln('  AppSettings._();');
    buf.writeln('  static final instance = AppSettings._();');
    buf.writeln();
    buf.writeln('  SharedPreferences? _prefs;');
    buf.writeln();
    buf.writeln('  Future<void> initialize() async {');
    buf.writeln('    _prefs = await SharedPreferences.getInstance();');
    buf.writeln('  }');
    buf.writeln();
    // Setting accessors
    for (final entry in app.settings.entries) {
      final key = entry.key;
      final setting = entry.value;
      switch (setting.type) {
        case 'checkbox':
          final def = setting.defaultValue?.toLowerCase() == 'true' ? 'true' : 'false';
          buf.writeln("  bool get${_toClassName(key)}() => _prefs?.getBool(${_dartString(key)}) ?? $def;");
          buf.writeln("  Future<void> set${_toClassName(key)}(bool value) async => _prefs?.setBool(${_dartString(key)}, value);");
        case 'number':
          final def = setting.defaultValue ?? '0';
          buf.writeln("  double get${_toClassName(key)}() => _prefs?.getDouble(${_dartString(key)}) ?? $def;");
          buf.writeln("  Future<void> set${_toClassName(key)}(double value) async => _prefs?.setDouble(${_dartString(key)}, value);");
        default:
          final def = setting.defaultValue != null ? _dartString(setting.defaultValue!) : "''";
          buf.writeln("  String get${_toClassName(key)}() => _prefs?.getString(${_dartString(key)}) ?? $def;");
          buf.writeln("  Future<void> set${_toClassName(key)}(String value) async => _prefs?.setString(${_dartString(key)}, value);");
      }
      buf.writeln();
    }
    // Theme mode
    buf.writeln("  ThemeMode getThemeMode() {");
    buf.writeln("    final value = _prefs?.getString('themeMode') ?? 'system';");
    buf.writeln("    return switch (value) {");
    buf.writeln("      'light' => ThemeMode.light,");
    buf.writeln("      'dark' => ThemeMode.dark,");
    buf.writeln("      _ => ThemeMode.system,");
    buf.writeln("    };");
    buf.writeln("  }");
    buf.writeln();
    buf.writeln("  Future<void> setThemeMode(ThemeMode mode) async {");
    buf.writeln("    final value = switch (mode) {");
    buf.writeln("      ThemeMode.light => 'light',");
    buf.writeln("      ThemeMode.dark => 'dark',");
    buf.writeln("      _ => 'system',");
    buf.writeln("    };");
    buf.writeln("    await _prefs?.setString('themeMode', value);");
    buf.writeln("  }");
    buf.writeln();
    // Tour state
    if (app.tour.isNotEmpty) {
      buf.writeln("  bool hasSeenTour() => _prefs?.getBool('tourSeen') ?? false;");
      buf.writeln("  Future<void> markTourSeen() async => _prefs?.setBool('tourSeen', true);");
      buf.writeln("  Future<void> resetTour() async => _prefs?.remove('tourSeen');");
    }
    buf.writeln('}');
    return buf.toString();
  }

  String _genSettingsDialog(OdsApp app) {
    final buf = StringBuffer();
    buf.writeln("import 'package:flutter/material.dart';");
    buf.writeln("import '../main.dart';");
    buf.writeln("import '../data/app_settings.dart';");
    buf.writeln();
    buf.writeln('class SettingsDialog extends StatefulWidget {');
    buf.writeln('  const SettingsDialog({super.key});');
    buf.writeln();
    buf.writeln('  @override');
    buf.writeln('  State<SettingsDialog> createState() => _SettingsDialogState();');
    buf.writeln('}');
    buf.writeln();
    buf.writeln('class _SettingsDialogState extends State<SettingsDialog> {');
    buf.writeln('  late ThemeMode _themeMode;');
    // State vars for each setting
    for (final entry in app.settings.entries) {
      final key = entry.key;
      final setting = entry.value;
      switch (setting.type) {
        case 'checkbox':
          buf.writeln('  late bool _$key;');
        case 'number':
          buf.writeln('  late double _$key;');
        default:
          buf.writeln('  late String _$key;');
      }
    }
    buf.writeln();
    buf.writeln('  @override');
    buf.writeln('  void initState() {');
    buf.writeln('    super.initState();');
    buf.writeln('    _themeMode = AppSettings.instance.getThemeMode();');
    for (final entry in app.settings.entries) {
      final key = entry.key;
      final className = _toClassName(key);
      buf.writeln('    _$key = AppSettings.instance.get$className();');
    }
    buf.writeln('  }');
    buf.writeln();
    buf.writeln('  @override');
    buf.writeln('  Widget build(BuildContext context) {');
    buf.writeln('    return AlertDialog(');
    buf.writeln("      title: const Text('Settings'),");
    buf.writeln('      content: SingleChildScrollView(');
    buf.writeln('        child: Column(');
    buf.writeln('          mainAxisSize: MainAxisSize.min,');
    buf.writeln('          crossAxisAlignment: CrossAxisAlignment.start,');
    buf.writeln('          children: [');
    // Theme toggle
    buf.writeln("            const Text('Mode', style: TextStyle(fontWeight: FontWeight.w600)),");
    buf.writeln('            DropdownButton<ThemeMode>(');
    buf.writeln('              value: _themeMode,');
    buf.writeln('              isExpanded: true,');
    buf.writeln('              items: const [');
    buf.writeln("                DropdownMenuItem(value: ThemeMode.system, child: Text('System default')),");
    buf.writeln("                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),");
    buf.writeln("                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),");
    buf.writeln('              ],');
    buf.writeln('              onChanged: (mode) {');
    buf.writeln('                if (mode != null) setState(() => _themeMode = mode);');
    buf.writeln('              },');
    buf.writeln('            ),');
    if (app.settings.isNotEmpty) {
      buf.writeln('            const Divider(),');
    }
    // App-specific settings
    for (final entry in app.settings.entries) {
      final key = entry.key;
      final setting = entry.value;
      switch (setting.type) {
        case 'checkbox':
          buf.writeln('            SwitchListTile(');
          buf.writeln("              title: Text(${_dartString(setting.label ?? key)}),");
          buf.writeln('              value: _$key,');
          buf.writeln('              contentPadding: EdgeInsets.zero,');
          buf.writeln('              onChanged: (v) => setState(() => _$key = v),');
          buf.writeln('            ),');
        case 'select':
          buf.writeln("            Text(${_dartString(setting.label ?? key)}, style: const TextStyle(fontWeight: FontWeight.w500)),");
          buf.writeln('            DropdownButton<String>(');
          buf.writeln('              value: _$key.isNotEmpty ? _$key : null,');
          buf.writeln('              isExpanded: true,');
          buf.writeln('              items: const [');
          for (final opt in setting.options ?? []) {
            buf.writeln("                DropdownMenuItem(value: ${_dartString(opt)}, child: Text(${_dartString(opt)})),");
          }
          buf.writeln('              ],');
          buf.writeln('              onChanged: (v) { if (v != null) setState(() => _$key = v); },');
          buf.writeln('            ),');
        default:
          buf.writeln("            Text(${_dartString(setting.label ?? key)}, style: const TextStyle(fontWeight: FontWeight.w500)),");
          buf.writeln('            TextField(');
          buf.writeln("              controller: TextEditingController(text: _${key}.toString()),");
          buf.writeln('              onChanged: (v) => _$key = ${setting.type == 'number' ? 'double.tryParse(v) ?? _$key' : 'v'},');
          buf.writeln('              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),');
          buf.writeln('            ),');
          buf.writeln('            const SizedBox(height: 8),');
      }
    }
    buf.writeln('          ],');
    buf.writeln('        ),');
    buf.writeln('      ),');
    buf.writeln('      actions: [');
    buf.writeln("        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),");
    buf.writeln('        FilledButton(');
    buf.writeln("          child: const Text('Save'),");
    buf.writeln('          onPressed: () async {');
    buf.writeln('            await AppSettings.instance.setThemeMode(_themeMode);');
    buf.writeln('            MyApp.of(context).setThemeMode(_themeMode);');
    for (final entry in app.settings.entries) {
      final key = entry.key;
      final className = _toClassName(key);
      buf.writeln('            await AppSettings.instance.set$className(_$key);');
    }
    buf.writeln('            if (mounted) Navigator.pop(context);');
    buf.writeln('          },');
    buf.writeln('        ),');
    buf.writeln('      ],');
    buf.writeln('    );');
    buf.writeln('  }');
    buf.writeln('}');
    return buf.toString();
  }

  String _genHelpPage(OdsApp app) {
    final help = app.help!;
    final buf = StringBuffer();
    buf.writeln("import 'package:flutter/material.dart';");
    buf.writeln();
    buf.writeln('class HelpPage extends StatelessWidget {');
    buf.writeln('  const HelpPage({super.key});');
    buf.writeln();
    buf.writeln('  @override');
    buf.writeln('  Widget build(BuildContext context) {');
    buf.writeln('    return Scaffold(');
    buf.writeln("      appBar: AppBar(title: const Text('Help')),");
    buf.writeln('      body: ListView(');
    buf.writeln('        padding: const EdgeInsets.all(16),');
    buf.writeln('        children: [');
    if (help.overview.isNotEmpty) {
      buf.writeln('          Card(');
      buf.writeln('            child: Padding(');
      buf.writeln('              padding: const EdgeInsets.all(16),');
      buf.writeln('              child: Column(');
      buf.writeln('                crossAxisAlignment: CrossAxisAlignment.start,');
      buf.writeln('                children: [');
      buf.writeln("                  Text('Overview', style: Theme.of(context).textTheme.titleMedium),");
      buf.writeln('                  const SizedBox(height: 8),');
      buf.writeln("                  Text(${_dartString(help.overview)}),");
      buf.writeln('                ],');
      buf.writeln('              ),');
      buf.writeln('            ),');
      buf.writeln('          ),');
      buf.writeln('          const SizedBox(height: 8),');
    }
    for (final entry in help.pages.entries) {
      // Find page title from app
      final pageTitle = app.pages[entry.key]?.title ?? entry.key;
      buf.writeln('          Card(');
      buf.writeln('            child: Padding(');
      buf.writeln('              padding: const EdgeInsets.all(16),');
      buf.writeln('              child: Column(');
      buf.writeln('                crossAxisAlignment: CrossAxisAlignment.start,');
      buf.writeln('                children: [');
      buf.writeln("                  Text(${_dartString(pageTitle)}, style: Theme.of(context).textTheme.titleSmall),");
      buf.writeln('                  const SizedBox(height: 8),');
      buf.writeln("                  Text(${_dartString(entry.value)}),");
      buf.writeln('                ],');
      buf.writeln('              ),');
      buf.writeln('            ),');
      buf.writeln('          ),');
      buf.writeln('          const SizedBox(height: 8),');
    }
    buf.writeln('        ],');
    buf.writeln('      ),');
    buf.writeln('    );');
    buf.writeln('  }');
    buf.writeln('}');
    return buf.toString();
  }

  String _genTourDialog(OdsApp app) {
    final steps = app.tour;
    final buf = StringBuffer();
    buf.writeln("import 'package:flutter/material.dart';");
    buf.writeln();
    buf.writeln('/// Displays a multi-step guided tour dialog.');
    buf.writeln('class AppTourDialog extends StatefulWidget {');
    buf.writeln('  const AppTourDialog._();');
    buf.writeln();
    buf.writeln('  /// Shows the tour as a non-dismissible dialog.');
    buf.writeln('  static void show(BuildContext context) {');
    buf.writeln('    showDialog<void>(');
    buf.writeln('      context: context,');
    buf.writeln('      barrierDismissible: false,');
    buf.writeln('      builder: (_) => const AppTourDialog._(),');
    buf.writeln('    );');
    buf.writeln('  }');
    buf.writeln();
    buf.writeln('  @override');
    buf.writeln('  State<AppTourDialog> createState() => _AppTourDialogState();');
    buf.writeln('}');
    buf.writeln();
    buf.writeln('class _AppTourDialogState extends State<AppTourDialog> {');
    buf.writeln('  int _step = 0;');
    buf.writeln();
    buf.writeln('  static const _steps = [');
    for (final step in steps) {
      buf.writeln('    (title: ${_dartString(step.title)}, content: ${_dartString(step.content)}),');
    }
    buf.writeln('  ];');
    buf.writeln();
    buf.writeln('  @override');
    buf.writeln('  Widget build(BuildContext context) {');
    buf.writeln('    final total = _steps.length;');
    buf.writeln('    final step = _steps[_step];');
    buf.writeln('    return AlertDialog(');
    buf.writeln('      title: Text(step.title),');
    buf.writeln('      content: Column(');
    buf.writeln('        mainAxisSize: MainAxisSize.min,');
    buf.writeln('        crossAxisAlignment: CrossAxisAlignment.start,');
    buf.writeln('        children: [');
    buf.writeln('          LinearProgressIndicator(value: (_step + 1) / total),');
    buf.writeln('          const SizedBox(height: 16),');
    buf.writeln('          Text(step.content),');
    buf.writeln('          const SizedBox(height: 8),');
    buf.writeln("          Text('\${_step + 1} of \$total', style: Theme.of(context).textTheme.bodySmall),");
    buf.writeln('        ],');
    buf.writeln('      ),');
    buf.writeln('      actions: [');
    buf.writeln('        if (_step > 0)');
    buf.writeln('          TextButton(');
    buf.writeln("            onPressed: () => setState(() => _step--),");
    buf.writeln("            child: const Text('Back'),");
    buf.writeln('          ),');
    buf.writeln('        TextButton(');
    buf.writeln('          onPressed: () => Navigator.pop(context),');
    buf.writeln("          child: const Text('Skip'),");
    buf.writeln('        ),');
    buf.writeln('        FilledButton(');
    buf.writeln('          onPressed: () {');
    buf.writeln('            if (_step < total - 1) {');
    buf.writeln('              setState(() => _step++);');
    buf.writeln('            } else {');
    buf.writeln('              Navigator.pop(context);');
    buf.writeln('            }');
    buf.writeln('          },');
    buf.writeln("          child: Text(_step < total - 1 ? 'Next' : 'Done'),");
    buf.writeln('        ),');
    buf.writeln('      ],');
    buf.writeln('    );');
    buf.writeln('  }');
    buf.writeln('}');
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  /// Collects column names for a table from data source fields or forms.
  List<String> _collectColumns(String dsId, OdsDataSource ds, OdsApp app) {
    final columns = <String>{};

    // From explicit fields on the data source
    if (ds.fields != null) {
      for (final field in ds.fields!) {
        if (!field.isComputed) columns.add(field.name);
      }
    }

    // From forms that submit to this data source
    for (final page in app.pages.values) {
      for (final component in page.content) {
        if (component is OdsButtonComponent) {
          for (final action in component.onClick) {
            if (action.isSubmit && action.dataSource == dsId && action.target != null) {
              // Find the form
              for (final p in app.pages.values) {
                for (final c in p.content) {
                  if (c is OdsFormComponent && c.id == action.target) {
                    for (final f in c.fields) {
                      if (!f.isComputed) columns.add(f.name);
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    return columns.toList();
  }

  /// Converts a string to snake_case.
  String _toSnakeCase(String input) {
    return input
        .replaceAll(RegExp(r'[^\w]'), '_')
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (m) => '${m[1]}_${m[2]}',
        )
        .replaceAll(RegExp(r'_+'), '_')
        .toLowerCase()
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  /// Converts a page ID to a PascalCase class name.
  String _toClassName(String pageId) {
    return pageId
        .replaceAll(RegExp(r'[^\w]'), '_')
        .split(RegExp(r'[_\s]+'))
        .map((word) => word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}')
        .join();
  }

  /// Wraps a string as a Dart string literal, escaping as needed.
  String _dartString(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll(r'$', r'\$');
    return "'$escaped'";
  }
}
