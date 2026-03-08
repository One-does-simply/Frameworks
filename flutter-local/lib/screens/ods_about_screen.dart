import 'package:flutter/material.dart';

/// The built-in "About ODS" screen, accessible from the welcome screen.
///
/// This is a framework-level screen (not driven by spec JSON). It introduces
/// the ODS project to new users: what it is, how it works, the off-ramp
/// philosophy, and getting-started instructions.
///
/// ODS Ethos: The framework itself should be as approachable as the apps it
/// runs. This screen answers the first questions a new user has without
/// requiring them to leave the app or search the web.
class OdsAboutScreen extends StatelessWidget {
  const OdsAboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('About ODS')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // -- Brand header --
          Text(
            'One Does Simply',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '"One does not simply do complex things,\n'
            'but One Does Simply do simple things."',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontStyle: FontStyle.italic,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),

          // -- Informational cards --
          const _SectionCard(
            icon: Icons.lightbulb_outline,
            title: 'What is ODS?',
            body: 'ODS is an open-source project that lets you define simple applications '
                'using a JSON file. You describe what your app should do — its pages, forms, '
                'lists, and buttons — and an ODS Framework brings it to life.\n\n'
                'No coding required. No vendor lock-in. Your data stays on your device.',
          ),
          const _SectionCard(
            icon: Icons.architecture,
            title: 'How It Works',
            body: '1. Describe your app in a JSON specification file\n'
                '2. Open the spec in this framework\n'
                '3. The framework renders your app instantly\n\n'
                'You can create spec files with the ODS Build Helper (an AI assistant) '
                'or write them by hand.',
          ),
          const _SectionCard(
            icon: Icons.phone_android,
            title: 'This Framework',
            body: 'ODS-Framework-Flutter is the reference implementation. It runs your ODS '
                'apps completely on-device with local SQLite storage. No internet needed.\n\n'
                'Perfect for personal tools: trackers, journals, checklists, and more.',
          ),
          // The off-ramp is a core ODS differentiator — explain it clearly.
          const _SectionCard(
            icon: Icons.exit_to_app,
            title: 'The Off-Ramp',
            body: 'Unlike other low-code tools, ODS never locks you in. Your spec is a '
                'standard JSON file you own. In the future, frameworks will generate real '
                'source code from your spec, giving you a full codebase to customize.',
          ),
          const _SectionCard(
            icon: Icons.code,
            title: 'Open Source',
            body: 'ODS is open source and community-driven. Contributions are welcome!\n\n'
                'GitHub: github.com/cac2131/one-does-simply',
          ),
          const SizedBox(height: 16),
          const _SectionCard(
            icon: Icons.help_outline,
            title: 'Getting Started',
            body: 'From the home screen you can:\n\n'
                '  Open Spec File — load a .json spec from your device\n'
                '  Enter URL — fetch a spec from the web\n'
                '  Try Examples — explore built-in sample apps\n\n'
                'Once loaded, use the side menu to navigate between pages. '
                'Tap the bug icon to toggle debug mode for troubleshooting.',
          ),
        ],
      ),
    );
  }
}

/// A reusable card widget for the about screen's informational sections.
///
/// Each card has a leading icon, a bold title, and body text. The icon uses
/// the theme's primary color to maintain visual consistency.
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(body, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
