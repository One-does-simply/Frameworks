import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The "Learn More" screen — introduces ODS to new users.
///
/// Accessible from the welcome screen "Learn More" link. Leads with
/// the "Vibe Coding with Guardrails" message and explains the three
/// pillars of ODS: Specification, Frameworks, and the Build Helper.
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

                      // Lead with the core message
                      _SectionCard(
                        colorScheme: colorScheme,
                        icon: Icons.auto_awesome,
                        title: 'Vibe Coding with Guardrails',
                        body: 'Traditional vibe coding lets AI generate arbitrary code you may not '
                            'understand. ODS flips the model: describe your app idea and an AI Build '
                            'Helper produces a structured JSON spec — validated, human-readable, and '
                            'constrained to safe patterns.\n\n'
                            'The framework handles the hard parts — UI, storage, security — so the AI '
                            'never has to. You get the creative speed of vibe coding with the confidence '
                            'that your app actually works, your data is safe, and you\'re never locked in.',
                      ),
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
                        body: '1. Describe your app to the AI Build Helper (or write JSON by hand)\n'
                            '2. The Build Helper produces a valid ODS spec — that\'s the guardrail\n'
                            '3. Open the spec and the framework renders your app instantly\n\n'
                            'The spec stays simple. The framework handles the complexity. '
                            'And the AI can only produce specs that work.',
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
                        body: 'Unlike other platforms, ODS never locks you in. Your spec is a '
                            'standard JSON file you own. When you outgrow the framework, use Generate '
                            'Code to produce a full Flutter project — real source code with models, '
                            'database helpers, and UI widgets — and customize without limits.\n\n'
                            'ODS is the on-ramp to real development, not a dead end.',
                      ),
                      _LinksSectionCard(colorScheme: colorScheme),
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

class _LinksSectionCard extends StatelessWidget {
  final ColorScheme colorScheme;
  const _LinksSectionCard({required this.colorScheme});

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
                    child: Icon(Icons.code, size: 20, color: colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Open Source',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'ODS is open source and community-driven.',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 12),
              _LinkTile(
                icon: Icons.code,
                label: 'GitHub Repository',
                url: 'https://github.com/One-does-simply',
              ),
              _LinkTile(
                icon: Icons.language,
                label: 'Project Homepage',
                url: 'https://one-does-simply.github.io/Specification/index.html',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;
  const _LinkTile({required this.icon, required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w500),
              ),
            ),
            Icon(Icons.open_in_new, size: 14, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
