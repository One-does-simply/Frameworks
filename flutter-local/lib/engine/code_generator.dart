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

    // Imports
    buf.writeln("import 'package:flutter/material.dart';");
    buf.writeln("import 'package:sqflite_common_ffi/sqflite_ffi.dart';");
    buf.writeln("import 'data/database_helper.dart';");
    for (final pageId in app.pages.keys) {
      buf.writeln("import 'pages/${_toSnakeCase(pageId)}.dart';");
    }
    buf.writeln();

    // main()
    buf.writeln('void main() {');
    buf.writeln('  sqfliteFfiInit();');
    buf.writeln('  databaseFactory = databaseFactoryFfi;');
    buf.writeln('  runApp(const MyApp());');
    buf.writeln('}');
    buf.writeln();

    // MyApp widget
    buf.writeln('class MyApp extends StatelessWidget {');
    buf.writeln('  const MyApp({super.key});');
    buf.writeln();
    buf.writeln('  @override');
    buf.writeln('  Widget build(BuildContext context) {');
    buf.writeln('    return MaterialApp(');
    buf.writeln("      title: ${_dartString(app.appName)},");
    buf.writeln('      theme: ThemeData(');
    buf.writeln('        colorSchemeSeed: Colors.blue,');
    buf.writeln('        useMaterial3: true,');
    buf.writeln('      ),');
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
        buf.writeln("            _id INTEGER PRIMARY KEY AUTOINCREMENT,");
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
    final hasButtons = page.content.any((c) => c is OdsButtonComponent);

    // Imports
    buf.writeln("import 'package:flutter/material.dart';");
    if (hasChart) {
      buf.writeln("import 'package:fl_chart/fl_chart.dart';");
      buf.writeln("import 'dart:math' as math;");
    }
    buf.writeln("import '../data/database_helper.dart';");
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

    // List data state
    if (hasList || hasChart) {
      buf.writeln('  List<Map<String, dynamic>> _rows = [];');
      buf.writeln('  bool _loading = true;');
    }

    // Drawer menu reference
    final hasMenu = app.menu.isNotEmpty;

    buf.writeln();

    // initState
    if (hasList || hasChart) {
      buf.writeln('  @override');
      buf.writeln('  void initState() {');
      buf.writeln('    super.initState();');
      buf.writeln('    _loadData();');
      buf.writeln('  }');
      buf.writeln();
    }

    // initState for form defaults
    for (final component in page.content) {
      if (component is OdsFormComponent) {
        final hasDefaults = component.fields.any((f) => f.defaultValue != null && !f.isComputed);
        if (hasDefaults && !(hasList || hasChart)) {
          buf.writeln('  @override');
          buf.writeln('  void initState() {');
          buf.writeln('    super.initState();');
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
          buf.writeln('  }');
          buf.writeln();
        }
      }
    }

    // _loadData for list/chart pages
    if (hasList || hasChart) {
      // Find the data source table name
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
    buf.writeln('      appBar: AppBar(');
    buf.writeln("        title: Text(${_dartString(page.title)}),");
    buf.writeln('      ),');

    // Drawer
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
      buf.writeln('          ],');
      buf.writeln('        ),');
      buf.writeln('      ),');
    }

    // Body
    buf.writeln('      body: ListView(');
    buf.writeln('        padding: const EdgeInsets.all(16),');
    buf.writeln('        children: [');

    for (final component in page.content) {
      _genComponent(buf, component, app, pageId);
    }

    buf.writeln('        ],');
    buf.writeln('      ),');
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
      case OdsUnknownComponent _:
        buf.writeln("          // Unknown component type — skipped");
    }
  }

  void _genTextComponent(StringBuffer buf, OdsTextComponent c) {
    final variant = c.styleHint.variant;
    String? style;
    switch (variant) {
      case 'heading':
        style = 'Theme.of(context).textTheme.headlineSmall';
      case 'subheading':
        style = 'Theme.of(context).textTheme.titleMedium';
      case 'caption':
        style = 'Theme.of(context).textTheme.bodySmall';
    }

    buf.writeln('          Padding(');
    buf.writeln('            padding: const EdgeInsets.symmetric(vertical: 8),');
    buf.writeln('            child: Text(');
    buf.writeln('              ${_dartString(c.content)},');
    if (style != null) {
      buf.writeln('              style: $style,');
    }
    buf.writeln('            ),');
    buf.writeln('          ),');
  }

  void _genFormComponent(StringBuffer buf, OdsFormComponent c, OdsApp app) {
    buf.writeln('          Form(');
    buf.writeln('            key: _formKey,');
    buf.writeln('            child: Column(');
    buf.writeln('              children: [');

    for (final field in c.fields) {
      if (field.isComputed) {
        // Computed field — read-only display
        buf.writeln('                // Computed field: ${field.name}');
        buf.writeln('                Padding(');
        buf.writeln('                  padding: const EdgeInsets.symmetric(vertical: 8),');
        buf.writeln('                  child: Builder(builder: (context) {');
        // Generate a simple computation preview
        buf.writeln("                    // Formula: ${field.formula ?? ''}");
        buf.writeln('                    return TextFormField(');
        buf.writeln("                      decoration: InputDecoration(labelText: ${_dartString(field.label ?? field.name)}, enabled: false),");
        buf.writeln("                      controller: TextEditingController(text: 'Computed'),");
        buf.writeln('                    );');
        buf.writeln('                  }),');
        buf.writeln('                ),');
        continue;
      }

      final controllerName = '_${field.name}Controller';

      if (field.type == 'select' && field.options != null && field.options!.isNotEmpty) {
        _genSelectField(buf, field, controllerName);
      } else if (field.type == 'checkbox') {
        _genCheckboxField(buf, field, controllerName);
      } else if (field.type == 'date' || field.type == 'datetime') {
        _genDateField(buf, field, controllerName);
      } else if (field.type == 'multiline') {
        _genMultilineField(buf, field, controllerName);
      } else {
        _genTextField(buf, field, controllerName);
      }
    }

    buf.writeln('              ],');
    buf.writeln('            ),');
    buf.writeln('          ),');
  }

  void _genTextField(StringBuffer buf, OdsFieldDefinition field, String controllerName) {
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
    buf.writeln('                  ),');
    buf.writeln('                ),');
  }

  void _genMultilineField(StringBuffer buf, OdsFieldDefinition field, String controllerName) {
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
    buf.writeln('                  ),');
    buf.writeln('                ),');
  }

  void _genSelectField(StringBuffer buf, OdsFieldDefinition field, String controllerName) {
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
    buf.writeln('                    },');
    buf.writeln('                  ),');
    buf.writeln('                ),');
  }

  void _genCheckboxField(StringBuffer buf, OdsFieldDefinition field, String controllerName) {
    buf.writeln('                Padding(');
    buf.writeln('                  padding: const EdgeInsets.symmetric(vertical: 8),');
    buf.writeln('                  child: CheckboxListTile(');
    buf.writeln("                    title: Text(${_dartString(field.label ?? field.name)}),");
    buf.writeln("                    value: $controllerName.text == 'true',");
    buf.writeln('                    onChanged: (value) {');
    buf.writeln("                      setState(() { $controllerName.text = (value ?? false).toString(); });");
    buf.writeln('                    },');
    buf.writeln('                  ),');
    buf.writeln('                ),');
  }

  void _genDateField(StringBuffer buf, OdsFieldDefinition field, String controllerName) {
    buf.writeln('                Padding(');
    buf.writeln('                  padding: const EdgeInsets.symmetric(vertical: 8),');
    buf.writeln('                  child: TextFormField(');
    buf.writeln('                    controller: $controllerName,');
    buf.writeln('                    readOnly: true,');
    buf.writeln("                    decoration: InputDecoration(");
    buf.writeln("                      labelText: ${_dartString(field.label ?? field.name)},");
    buf.writeln("                      border: const OutlineInputBorder(),");
    buf.writeln("                      suffixIcon: const Icon(Icons.calendar_today),");
    buf.writeln("                    ),");
    buf.writeln('                    onTap: () async {');
    buf.writeln('                      final date = await showDatePicker(');
    buf.writeln('                        context: context,');
    buf.writeln('                        initialDate: DateTime.now(),');
    buf.writeln('                        firstDate: DateTime(2000),');
    buf.writeln('                        lastDate: DateTime(2100),');
    buf.writeln('                      );');
    buf.writeln('                      if (date != null) {');
    buf.writeln("                        $controllerName.text = date.toIso8601String().split('T')[0];");
    buf.writeln('                      }');
    buf.writeln('                    },');
    buf.writeln('                  ),');
    buf.writeln('                ),');
  }

  void _genListComponent(StringBuffer buf, OdsListComponent c, OdsApp app) {
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
    buf.writeln('                  return DataRow(cells: [');
    for (final col in c.columns) {
      buf.writeln("                    DataCell(Text(row[${_dartString(col.field)}]?.toString() ?? '')),");
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
    final isSecondary = emphasis == 'secondary';
    final isDanger = emphasis == 'danger';
    final widgetType = isSecondary ? 'OutlinedButton' : 'ElevatedButton';

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
    buf.writeln("              child: Text(${_dartString(c.label)}),");
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
