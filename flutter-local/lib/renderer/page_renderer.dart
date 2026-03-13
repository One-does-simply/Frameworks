import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/app_engine.dart';
import '../models/ods_component.dart';
import '../models/ods_page.dart';
import '../models/ods_visible_when.dart';
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
/// Components with a `visibleWhen` condition are wrapped in a visibility
/// check that evaluates form field values or data source row counts.
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

  /// Dispatches each component model to its corresponding widget,
  /// wrapping it in a visibility check if a `visibleWhen` condition exists.
  Widget _renderComponent(OdsComponent component) {
    final widget = switch (component) {
      OdsTextComponent c => OdsTextWidget(model: c, styleResolver: styleResolver),
      OdsListComponent c => OdsListWidget(model: c),
      OdsFormComponent c => OdsFormWidget(model: c),
      OdsButtonComponent c => OdsButtonWidget(model: c, styleResolver: styleResolver),
      OdsChartComponent c => OdsChartWidget(model: c),
      OdsUnknownComponent c => _UnknownComponentWidget(model: c),
    };

    // Wrap with visibility check if condition is set.
    if (component.visibleWhen != null) {
      return _VisibilityWrapper(
        condition: component.visibleWhen!,
        child: widget,
      );
    }

    return widget;
  }
}

/// Wraps a component widget with a visibility condition.
///
/// For field-based conditions, watches form state via the engine.
/// For data-based conditions, queries the data source row count.
class _VisibilityWrapper extends StatelessWidget {
  final OdsComponentVisibleWhen condition;
  final Widget child;

  const _VisibilityWrapper({required this.condition, required this.child});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AppEngine>();

    if (condition.isFieldBased) {
      return _buildFieldBased(engine);
    }

    if (condition.isDataBased) {
      return _buildDataBased(engine);
    }

    // Invalid condition — show the component by default.
    return child;
  }

  Widget _buildFieldBased(AppEngine engine) {
    final formState = engine.getFormState(condition.form!);
    final fieldValue = formState[condition.field!] ?? '';

    bool visible = true;
    if (condition.equals != null) {
      visible = fieldValue == condition.equals;
    } else if (condition.notEquals != null) {
      visible = fieldValue != condition.notEquals;
    }

    if (!visible) return const SizedBox.shrink();
    return child;
  }

  Widget _buildDataBased(AppEngine engine) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: engine.queryDataSource(condition.source!),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final count = snapshot.data!.length;
        bool visible = true;

        if (condition.countEquals != null) {
          visible = count == condition.countEquals;
        }
        if (visible && condition.countMin != null) {
          visible = count >= condition.countMin!;
        }
        if (visible && condition.countMax != null) {
          visible = count <= condition.countMax!;
        }

        if (!visible) return const SizedBox.shrink();
        return child;
      },
    );
  }
}

/// Renders unknown component types — invisible in normal mode, shown as a
/// warning card in debug mode.
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
