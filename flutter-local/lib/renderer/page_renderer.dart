import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/app_engine.dart';
import '../models/ods_component.dart';
import '../models/ods_page.dart';
import 'components/button_component.dart';
import 'components/chart_component.dart';
import 'components/form_component.dart';
import 'components/list_component.dart';
import 'components/text_component.dart';
import 'style_resolver.dart';

/// Renders an [OdsPage] by mapping its component array to Flutter widgets.
///
/// ODS Spec alignment: Each page's `content` array is rendered top-to-bottom
/// in a scrollable list. The renderer uses Dart 3 exhaustive switch on the
/// sealed [OdsComponent] class, guaranteeing at compile time that every
/// component type is handled.
///
/// ODS Ethos: Pages are simple — a vertical stack of components. No grid
/// layouts, no columns, no overlapping. This makes the rendering predictable
/// and the spec easy to reason about.
///
/// Architecture note: The [StyleResolver] is injected as a parameter to
/// support future theming or custom style resolution without modifying
/// component widgets.
class PageRenderer extends StatelessWidget {
  final OdsPage page;
  final StyleResolver styleResolver;

  const PageRenderer({
    super.key,
    required this.page,
    this.styleResolver = const StyleResolver(),
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: page.content.map((component) => _renderComponent(component)).toList(),
    );
  }

  /// Dispatches each component model to its corresponding widget.
  /// The exhaustive switch ensures new component types added to the sealed
  /// class will cause a compile error here until handled.
  Widget _renderComponent(OdsComponent component) {
    return switch (component) {
      OdsTextComponent c => OdsTextWidget(model: c, styleResolver: styleResolver),
      OdsListComponent c => OdsListWidget(model: c),
      OdsFormComponent c => OdsFormWidget(model: c),
      OdsButtonComponent c => OdsButtonWidget(model: c, styleResolver: styleResolver),
      OdsChartComponent c => OdsChartWidget(model: c),
      OdsUnknownComponent c => _UnknownComponentWidget(model: c),
    };
  }
}

/// Renders unknown component types — invisible in normal mode, shown as a
/// warning card in debug mode.
///
/// ODS Ethos: Graceful degradation. A spec with future component types
/// will still load and render the parts this framework understands.
class _UnknownComponentWidget extends StatelessWidget {
  final OdsUnknownComponent model;

  const _UnknownComponentWidget({required this.model});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AppEngine>();
    if (!engine.debugMode) return const SizedBox.shrink();

    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Unknown component: "${model.component}"',
          style: TextStyle(color: Colors.orange.shade800, fontStyle: FontStyle.italic),
        ),
      ),
    );
  }
}
