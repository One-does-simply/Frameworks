import 'package:flutter/material.dart';

import '../../models/ods_component.dart';
import '../style_resolver.dart';

/// Renders an [OdsTextComponent] as a styled Text widget.
///
/// ODS Spec: The text component is the simplest building block — just a
/// content string and an optional styleHint. The StyleResolver maps the
/// hint's `variant` (heading, subheading, body, caption) to a TextStyle.
class OdsTextWidget extends StatelessWidget {
  final OdsTextComponent model;
  final StyleResolver styleResolver;

  const OdsTextWidget({
    super.key,
    required this.model,
    this.styleResolver = const StyleResolver(),
  });

  @override
  Widget build(BuildContext context) {
    final style = styleResolver.resolveTextStyle(model.styleHint, context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(model.content, style: style),
    );
  }
}
