import 'package:flutter/material.dart';

/// The "Learn More" screen — introduces ODS to new users.
///
/// Accessible from the welcome screen "Learn More" link. Contains all
/// the informational content that was previously in the banner, plus
/// expanded details about the project.
class OdsAboutScreen extends StatelessWidget {
  const OdsAboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('About One Does Simply'),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [const Color(0xFF1E1B4B), const Color(0xFF0F172A)]
                        : [const Color(0xFF4F46E5), const Color(0xFF7C3AED)],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tagline
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.format_quote, size: 32, color: colorScheme.primary),
                            const SizedBox(height: 8),
                            Text(
                              '"One does not simply do complex things,\n'
                              'but One Does Simply do simple things."',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontStyle: FontStyle.italic,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      _SectionCard(
                        colorScheme: colorScheme,
                        icon: Icons.lightbulb_outline,
                        title: 'What is ODS?',
                        body: 'ODS is an open-source project that lets you define simple applications '
                            'using a JSON file. You describe what your app should do — its pages, forms, '
                            'lists, and buttons — and an ODS Framework brings it to life.\n\n'
                            'No coding required. No vendor lock-in. Your data stays on your device.',
                      ),
                      _SectionCard(
                        colorScheme: colorScheme,
                        icon: Icons.architecture,
                        title: 'How It Works',
                        body: '1. Describe your app in a JSON specification file\n'
                            '2. Open the spec in this framework\n'
                            '3. The framework renders your app instantly\n\n'
                            'You can create spec files with the ODS Build Helper (an AI assistant) '
                            'or write them by hand.',
                      ),
                      _SectionCard(
                        colorScheme: colorScheme,
                        icon: Icons.phone_android,
                        title: 'Flutter Local Framework',
                        body: 'This is the Flutter Local reference implementation. It runs your ODS '
                            'apps completely on-device with local SQLite storage. No internet needed.\n\n'
                            'Perfect for personal tools: trackers, journals, checklists, and more.',
                      ),
                      _SectionCard(
                        colorScheme: colorScheme,
                        icon: Icons.exit_to_app,
                        title: 'The Off-Ramp',
                        body: 'Unlike other low-code tools, ODS never locks you in. Your spec is a '
                            'standard JSON file you own. In the future, frameworks will generate real '
                            'source code from your spec, giving you a full codebase to customize.',
                      ),
                      _SectionCard(
                        colorScheme: colorScheme,
                        icon: Icons.auto_awesome,
                        title: 'Vibe Coding with Guardrails',
                        body: 'ODS embraces the vibe coding philosophy — describe what you want and '
                            'let AI help build it. But unlike unconstrained AI coding, ODS provides '
                            'guardrails: a well-defined spec, validation, and frameworks that ensure '
                            'your app actually works.',
                      ),
                      _SectionCard(
                        colorScheme: colorScheme,
                        icon: Icons.code,
                        title: 'Open Source',
                        body: 'ODS is open source and community-driven.\n\n'
                            'GitHub: github.com/One-does-simply',
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final ColorScheme colorScheme;
  final IconData icon;
  final String title;
  final String body;

  const _SectionCard({
    required this.colorScheme,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 20, color: colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(body, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
            ],
          ),
        ),
      ),
    );
  }
}
