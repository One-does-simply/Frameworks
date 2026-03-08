import 'package:flutter/material.dart';

import '../models/ods_help.dart';

/// A full-screen help view for an ODS app.
///
/// ODS Spec: The `help` object contains an `overview` string and an optional
/// `pages` map keyed by page ID. This screen renders the overview at the top
/// followed by a card for each page that has help text.
///
/// ODS Ethos: Apps should be self-documenting. The help screen is always one
/// tap away (the ? icon in the app bar) and requires zero external tooling
/// to author — the spec author simply writes plain-text descriptions inline.
///
/// The [pageTitles] map is passed in from the host so that page IDs (which
/// are developer-facing identifiers like "addExpense") are displayed as
/// their human-readable titles (like "Add Expense").
class AppHelpScreen extends StatelessWidget {
  final OdsHelp help;
  final String appName;
  final Map<String, String> pageTitles;

  const AppHelpScreen({
    super.key,
    required this.help,
    required this.appName,
    required this.pageTitles,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('$appName Help')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // -- App-level overview --
          Text(
            'Overview',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(help.overview, style: theme.textTheme.bodyLarge),

          // -- Per-page help cards --
          if (help.pages.isNotEmpty) ...[
            const SizedBox(height: 32),
            Text(
              'Page Guide',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...help.pages.entries.map((entry) {
              // Resolve the page ID to its human-readable title, falling
              // back to the raw ID if not found (graceful degradation).
              final pageTitle = pageTitles[entry.key] ?? entry.key;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pageTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(entry.value, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
