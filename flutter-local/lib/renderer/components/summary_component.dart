import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/aggregate_evaluator.dart';
import '../../engine/app_engine.dart';
import '../../models/ods_component.dart';
import '../style_resolver.dart';

/// Renders an [OdsSummaryComponent] as a styled KPI card.
///
/// Shows a label, a large aggregate value, and an optional icon.
/// The value expression supports aggregate syntax like
/// `{SUM(expenses, amount)}` or `{COUNT(tasks)}`.
///
/// Style hints:
///   - `color`: accent color for the card's left border stripe and icon tint
///   - `icon`: overrides the model's icon property (styleHint takes precedence)
///   - `size`: "compact" (smaller card) or "large" (hero KPI)
///   - `elevation`: 0–3 for shadow depth
class OdsSummaryWidget extends StatelessWidget {
  final OdsSummaryComponent model;
  final StyleResolver styleResolver;

  const OdsSummaryWidget({
    super.key,
    required this.model,
    this.styleResolver = const StyleResolver(),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final engine = context.watch<AppEngine>();
    final hint = model.styleHint;

    // Resolve accent color for the card.
    final accentColor = styleResolver.resolveColor(hint.color, context)
        ?? theme.colorScheme.primary;
    final tintColor = theme.brightness == Brightness.light
        ? accentColor.withValues(alpha: 0.06)
        : accentColor.withValues(alpha: 0.10);

    // Resolve icon from the model or style hint.
    final iconName = hint.icon ?? model.icon;
    final iconData = iconName != null
        ? (StyleResolver.resolveIcon(iconName) ?? _legacyResolveIcon(iconName))
        : null;

    // Size-dependent styling.
    final isCompact = hint.size == 'compact';
    final isLarge = hint.size == 'large';
    final iconSize = isCompact ? 28.0 : isLarge ? 52.0 : 40.0;
    final padding = isCompact
        ? const EdgeInsets.all(12.0)
        : isLarge
            ? const EdgeInsets.all(28.0)
            : const EdgeInsets.all(20.0);
    final borderWidth = isCompact ? 3.0 : 4.0;
    final elevation = hint.elevation?.toDouble() ?? (isCompact ? 0 : 1);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Card(
        elevation: elevation,
        color: tintColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: accentColor, width: borderWidth),
            ),
          ),
          padding: padding,
          child: Row(
            children: [
              if (iconData != null) ...[
                Container(
                  padding: EdgeInsets.all(isCompact ? 6 : 10),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(isCompact ? 8 : 12),
                  ),
                  child: Icon(
                    iconData,
                    size: iconSize,
                    color: accentColor,
                  ),
                ),
                SizedBox(width: isCompact ? 12 : 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: isLarge ? 14 : null,
                        letterSpacing: 0.3,
                      ),
                    ),
                    SizedBox(height: isCompact ? 2 : 4),
                    _buildValue(engine, theme, accentColor, isCompact, isLarge),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildValue(
    AppEngine engine,
    ThemeData theme,
    Color accentColor,
    bool isCompact,
    bool isLarge,
  ) {
    final valueStyle = isCompact
        ? theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          )
        : isLarge
            ? theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: accentColor,
              )
            : theme.textTheme.headlineMedium?.copyWith(
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

  /// Legacy icon map for backwards compatibility with existing specs that use
  /// names not in the StyleResolver's master map.
  static IconData _legacyResolveIcon(String name) {
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
      'checklist': Icons.checklist,
    };
    return iconMap[name] ?? Icons.summarize;
  }
}
