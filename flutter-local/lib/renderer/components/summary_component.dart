import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/aggregate_evaluator.dart';
import '../../engine/app_engine.dart';
import '../../models/ods_component.dart';

/// Renders an [OdsSummaryComponent] as a styled KPI card.
///
/// Shows a label, a large aggregate value, and an optional icon.
/// The value expression supports aggregate syntax like
/// `{SUM(expenses, amount)}` or `{COUNT(tasks)}`.
class OdsSummaryWidget extends StatelessWidget {
  final OdsSummaryComponent model;

  const OdsSummaryWidget({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final engine = context.watch<AppEngine>();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              if (model.icon != null) ...[
                Icon(
                  _resolveIcon(model.icon!),
                  size: 40,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildValue(engine, theme),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildValue(AppEngine engine, ThemeData theme) {
    final valueStyle = theme.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurface,
    );

    if (!AggregateEvaluator.hasAggregates(model.value)) {
      return Text(model.value, style: valueStyle);
    }

    return FutureBuilder<String>(
      future: AggregateEvaluator.resolve(
        model.value,
        engine.queryDataSource,
      ),
      builder: (context, snapshot) {
        final text = snapshot.data ?? '...';
        return Text(text, style: valueStyle);
      },
    );
  }

  /// Maps common icon name strings to Material IconData.
  static IconData _resolveIcon(String name) {
    const iconMap = <String, IconData>{
      'attach_money': Icons.attach_money,
      'money': Icons.attach_money,
      'trending_up': Icons.trending_up,
      'trending_down': Icons.trending_down,
      'people': Icons.people,
      'person': Icons.person,
      'check_circle': Icons.check_circle,
      'check': Icons.check,
      'warning': Icons.warning,
      'error': Icons.error,
      'info': Icons.info,
      'star': Icons.star,
      'favorite': Icons.favorite,
      'shopping_cart': Icons.shopping_cart,
      'inventory': Icons.inventory,
      'task': Icons.task,
      'timer': Icons.timer,
      'calendar_today': Icons.calendar_today,
      'schedule': Icons.schedule,
      'bar_chart': Icons.bar_chart,
      'pie_chart': Icons.pie_chart,
      'analytics': Icons.analytics,
      'dashboard': Icons.dashboard,
      'receipt': Icons.receipt,
      'local_offer': Icons.local_offer,
      'category': Icons.category,
      'list': Icons.list,
      'done': Icons.done,
      'done_all': Icons.done_all,
      'visibility': Icons.visibility,
      'speed': Icons.speed,
      'fitness_center': Icons.fitness_center,
      'restaurant': Icons.restaurant,
      'book': Icons.book,
      'school': Icons.school,
      'work': Icons.work,
      'home': Icons.home,
      'flight': Icons.flight,
      'directions_car': Icons.directions_car,
    };
    return iconMap[name] ?? Icons.summarize;
  }
}
