import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/app_engine.dart';
import '../../models/ods_component.dart';
import '../style_resolver.dart';

/// Renders an [OdsButtonComponent] as a Material ElevatedButton.
///
/// ODS Spec: Buttons have a label, an onClick action array, and an optional
/// styleHint with an `emphasis` key (primary, secondary, danger). Tapping
/// the button executes all actions in sequence.
///
/// ODS Ethos: Buttons are the only interactive element besides forms. They
/// do exactly two things: navigate somewhere or submit a form. This
/// constraint makes ODS apps predictable — every button tap either shows
/// you something new or saves what you entered.
///
/// When an action fails (e.g., required fields are missing), the engine
/// sets [AppEngine.lastActionError] and this widget shows it as a SnackBar
/// so the user gets immediate, clear feedback.
class OdsButtonWidget extends StatelessWidget {
  final OdsButtonComponent model;
  final StyleResolver styleResolver;

  const OdsButtonWidget({
    super.key,
    required this.model,
    this.styleResolver = const StyleResolver(),
  });

  @override
  Widget build(BuildContext context) {
    final style = styleResolver.resolveButtonStyle(model.styleHint, context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ElevatedButton(
        style: style,
        onPressed: () async {
          final engine = context.read<AppEngine>();
          await engine.executeActions(model.onClick);

          // Show a SnackBar if an action failed (e.g., required validation).
          if (engine.lastActionError != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(engine.lastActionError!),
                backgroundColor: Colors.red.shade700,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        child: Text(model.label),
      ),
    );
  }
}
