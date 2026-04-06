import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/app_engine.dart';
import '../engine/expression_evaluator.dart';
import '../models/ods_component.dart';
import '../models/ods_page.dart';
import '../models/ods_visible_when.dart';
import 'components/button_component.dart';
import 'components/chart_component.dart';
import 'components/detail_component.dart';
import 'components/form_component.dart';
import 'components/kanban_widget.dart';
import 'components/list_component.dart';
import 'components/summary_component.dart';
import 'components/tabs_component.dart';
import 'components/text_component.dart';
import 'style_resolver.dart';

/// Renders an [OdsPage] by mapping its component array to Flutter widgets.
///
/// Components with a `visibleWhen` or `visible` condition are wrapped in a
/// visibility check. The renderer uses Dart 3 exhaustive switch on the sealed
/// [OdsComponent] class, guaranteeing at compile time that every component
/// type is handled.
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
      children: page.content.map((component) => renderComponent(component, styleResolver)).toList(),
    );
  }

  /// Dispatches each component model to its corresponding widget,
  /// wrapping it in visibility checks if conditions exist.
  ///
  /// Made static so that tabs and other nested containers can reuse it.
  static Widget renderComponent(OdsComponent component, StyleResolver styleResolver) {
    Widget widget = switch (component) {
      OdsTextComponent c => OdsTextWidget(model: c, styleResolver: styleResolver),
      OdsListComponent c => OdsListWidget(model: c),
      OdsFormComponent c => OdsFormWidget(model: c),
      OdsButtonComponent c => OdsButtonWidget(model: c, styleResolver: styleResolver),
      OdsChartComponent c => OdsChartWidget(model: c),
      OdsSummaryComponent c => OdsSummaryWidget(model: c),
      OdsTabsComponent c => OdsTabsWidget(model: c, styleResolver: styleResolver),
      OdsDetailComponent c => OdsDetailWidget(model: c),
      OdsKanbanComponent c => OdsKanbanWidget(model: c),
      OdsUnknownComponent c => _UnknownComponentWidget(model: c),
    };

    // Wrap with structured visibility check if condition is set.
    if (component.visibleWhen != null) {
      widget = _VisibilityWrapper(
        condition: component.visibleWhen!,
        child: widget,
      );
    }

    // Wrap with expression-based visibility if set.
    if (component.visible != null) {
      widget = _ExpressionVisibilityWrapper(
        expression: component.visible!,
        child: widget,
      );
    }

    // Wrap with role-based visibility if roles are set.
    if (component.roles != null && component.roles!.isNotEmpty) {
      widget = _RoleVisibilityWrapper(
        requiredRoles: component.roles!,
        child: widget,
      );
    }

    return widget;
  }
}

/// Wraps a component widget with a structured visibility condition.
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

/// Wraps a component widget with an expression-based visibility check.
///
/// Evaluates the expression against all current form state values.
class _ExpressionVisibilityWrapper extends StatelessWidget {
  final String expression;
  final Widget child;

  const _ExpressionVisibilityWrapper({
    required this.expression,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AppEngine>();

    // Collect all form state values into a flat map.
    final values = <String, String>{};
    for (final formState in engine.allFormStates.values) {
      values.addAll(formState);
    }

    final visible = ExpressionEvaluator.evaluateBool(expression, values);
    if (!visible) return const SizedBox.shrink();
    return child;
  }
}

/// Renders unknown component types — invisible in normal mode, shown as a
/// warning card in debug mode.
/// Hides a component when the current user lacks the required roles.
/// In single-user mode (no auth), this always shows the child.
class _RoleVisibilityWrapper extends StatelessWidget {
  final List<String> requiredRoles;
  final Widget child;

  const _RoleVisibilityWrapper({required this.requiredRoles, required this.child});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AppEngine>();
    if (!engine.isMultiUser || engine.authService.hasAccess(requiredRoles)) {
      return child;
    }
    return const SizedBox.shrink();
  }
}

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
