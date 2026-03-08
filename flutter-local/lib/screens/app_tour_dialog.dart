import 'package:flutter/material.dart';

import '../models/ods_help.dart';

/// A step-by-step guided tour dialog for ODS apps.
///
/// ODS Spec: The `tour` array in the spec defines an ordered list of steps,
/// each with a `title`, `content`, and optional `page` reference. The
/// framework presents them sequentially and navigates to the referenced
/// page when a step declares one.
///
/// ODS Ethos: Every app should be self-explanatory. The tour is the app
/// developer's way of walking a new user through the experience — no
/// external documentation needed. It runs automatically on first launch
/// and can be replayed at any time via the toolbar.
///
/// UI: A modal [AlertDialog] with Back / Skip Tour / Next buttons and a
/// linear progress indicator. Non-dismissible by tapping outside so the
/// user makes an intentional choice (Next or Skip).
class AppTourDialog extends StatefulWidget {
  final List<OdsTourStep> steps;
  final String appName;

  /// Optional callback that the dialog invokes when a step has a `page`
  /// reference, allowing the host (AppShell) to navigate the engine.
  final void Function(String pageId)? onNavigateToPage;

  const AppTourDialog({
    super.key,
    required this.steps,
    required this.appName,
    this.onNavigateToPage,
  });

  /// Convenience factory that shows the dialog via [showDialog].
  ///
  /// Keeping the show logic here keeps the call site (AppShell) clean —
  /// one line to launch the tour.
  static Future<void> show(
    BuildContext context, {
    required List<OdsTourStep> steps,
    required String appName,
    void Function(String pageId)? onNavigateToPage,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AppTourDialog(
        steps: steps,
        appName: appName,
        onNavigateToPage: onNavigateToPage,
      ),
    );
  }

  @override
  State<AppTourDialog> createState() => _AppTourDialogState();
}

class _AppTourDialogState extends State<AppTourDialog> {
  int _currentStep = 0;

  bool get _isFirst => _currentStep == 0;
  bool get _isLast => _currentStep == widget.steps.length - 1;

  /// Advances to the next step, or closes the dialog on the last step.
  /// If the new step references a page, navigates the app to that page
  /// so the user sees the relevant context behind the dialog.
  void _next() {
    if (_isLast) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _currentStep++);
    _navigateIfNeeded(widget.steps[_currentStep]);
  }

  /// Goes back one step. No-op on the first step (button is hidden, but
  /// this guard prevents accidents).
  void _previous() {
    if (_isFirst) return;
    setState(() => _currentStep--);
    _navigateIfNeeded(widget.steps[_currentStep]);
  }

  /// If [step] declares a `page`, tells the host to navigate there.
  void _navigateIfNeeded(OdsTourStep step) {
    if (step.page != null && widget.onNavigateToPage != null) {
      widget.onNavigateToPage!(step.page!);
    }
  }

  @override
  void initState() {
    super.initState();
    // Navigate to the first step's page immediately so the user sees
    // the correct screen before reading the first tour card.
    _navigateIfNeeded(widget.steps[0]);
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_currentStep];
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.tour, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(step.title)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, minHeight: 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(step.content, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 16),
            // Step counter and progress bar give the user a sense of
            // how long the tour is — reduces abandonment.
            Text(
              'Step ${_currentStep + 1} of ${widget.steps.length}',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: (_currentStep + 1) / widget.steps.length,
            ),
          ],
        ),
      ),
      actions: [
        // Back button hidden on the first step — no confusing dead-end.
        if (!_isFirst)
          TextButton(
            onPressed: _previous,
            child: const Text('Back'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Skip Tour'),
        ),
        ElevatedButton(
          onPressed: _next,
          child: Text(_isLast ? 'Get Started' : 'Next'),
        ),
      ],
    );
  }
}
