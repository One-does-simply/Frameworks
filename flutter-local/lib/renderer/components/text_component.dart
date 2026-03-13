import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/aggregate_evaluator.dart';
import '../../engine/app_engine.dart';
import '../../models/ods_component.dart';
import '../style_resolver.dart';

/// Renders an [OdsTextComponent] as a styled Text widget.
///
/// ODS Spec: The text component displays content with an optional styleHint.
/// If the content contains aggregate references like `{SUM(expenses, amount)}`,
/// the component becomes data-aware and resolves them at runtime.
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

    // Fast path: no aggregates → simple static text.
    if (!AggregateEvaluator.hasAggregates(model.content)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(model.content, style: style),
      );
    }

    // Data-aware path: resolve aggregate references.
    final engine = context.watch<AppEngine>();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: FutureBuilder<String>(
        future: AggregateEvaluator.resolve(
          model.content,
          engine.queryDataSource,
        ),
        builder: (context, snapshot) {
          final text = snapshot.data ?? model.content;
          return Text(text, style: style);
        },
      ),
    );
  }
}
