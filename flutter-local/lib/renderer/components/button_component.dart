import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/app_engine.dart';
import '../../models/ods_component.dart';
import '../snackbar_helper.dart';
import '../style_resolver.dart';

/// Renders an [OdsButtonComponent] as a Material button.
///
/// ODS Spec: Buttons have a label, an onClick action array, and an optional
/// styleHint with:
///   - `emphasis`: "primary", "secondary", "danger" → color
///   - `variant`: "filled" (default), "outlined", "text", "tonal" → shape
///   - `icon`: Material icon name → leading icon
///   - `size`: "compact", "default", "large" → size scaling
///   - `color`: named/semantic color → custom accent override
///
/// ODS Ethos: Buttons are the only interactive element besides forms. They
/// do exactly two things: navigate somewhere or submit a form. This
/// constraint makes ODS apps predictable — every button tap either shows
/// you something new or saves what you entered.
class OdsButtonWidget extends StatelessWidget {
  final OdsButtonComponent model;
  final StyleResolver styleResolver;

  const OdsButtonWidget({
    super.key,
    required this.model,
    this.styleResolver = const StyleResolver(),
  });

  /// Shows a confirmation dialog and returns true if the user confirms.
  Future<bool> _showConfirmation(BuildContext context, String message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    final style = styleResolver.resolveButtonStyle(model.styleHint, context);
    final iconData = StyleResolver.resolveIcon(model.styleHint.icon);

    // Build the button content — icon + label or just label.
    Widget child;
    if (iconData != null) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: model.styleHint.size == 'compact' ? 16 : 18),
          const SizedBox(width: 8),
          Text(model.label),
        ],
      );
    } else {
      child = Text(model.label);
    }

    final onPressed = () async {
      final engine = context.read<AppEngine>();

      await engine.executeActions(
        model.onClick,
        confirmFn: (message) async {
          if (!context.mounted) return false;
          return await _showConfirmation(context, message);
        },
      );

      if (!context.mounted) return;

      if (engine.lastActionError != null) {
        showOdsSnackBar(context, message: engine.lastActionError!, isError: true);
      }

      if (engine.lastMessage != null) {
        showOdsSnackBar(context, message: engine.lastMessage!);
      }
    };

    // Pick the right widget type based on variant.
    Widget button;
    if (styleResolver.isOutlinedVariant(model.styleHint)) {
      button = OutlinedButton(
        style: style,
        onPressed: onPressed,
        child: child,
      );
    } else if (styleResolver.isTextVariant(model.styleHint)) {
      button = TextButton(
        style: style,
        onPressed: onPressed,
        child: child,
      );
    } else {
      button = ElevatedButton(
        style: style,
        onPressed: onPressed,
        child: child,
      );
    }

    // Apply alignment from style hint.
    final align = model.styleHint.align;
    if (align == 'center') {
      button = Center(child: button);
    } else if (align == 'right') {
      button = Align(alignment: Alignment.centerRight, child: button);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: button,
    );
  }
}
