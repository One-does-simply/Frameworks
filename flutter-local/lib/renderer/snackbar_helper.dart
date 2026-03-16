import 'package:flutter/material.dart';

/// Centralized SnackBar helper for the ODS framework.
///
/// Shows floating snackbars with a close button and auto-dismiss.
/// The default duration is 60 seconds (configurable via [duration]).
void showOdsSnackBar(
  BuildContext context, {
  required String message,
  bool isError = false,
  Duration duration = const Duration(seconds: 60),
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.of(context);
  // Clear any existing snackbar before showing a new one.
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          if (isError)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.error_outline, color: Colors.white, size: 20),
            ),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: isError ? Colors.red.shade700 : null,
      duration: duration,
      action: action,
      showCloseIcon: true,
      closeIconColor: Colors.white,
    ),
  );
}
