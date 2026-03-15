import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/app_engine.dart';
import '../../models/ods_component.dart';

/// Renders an [OdsDetailComponent] as a read-only card showing field
/// values from a data source record or form state.
///
/// Ideal for "view record" pages where the user navigates from a list
/// row and sees the full record details without a form.
class OdsDetailWidget extends StatelessWidget {
  /// Width allocated for field labels in the detail card layout.
  static const double _labelWidth = 120;
  final OdsDetailComponent model;

  const OdsDetailWidget({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AppEngine>();

    // If fromForm is set, read from form state directly.
    if (model.fromForm != null) {
      final formState = engine.getFormState(model.fromForm!);
      return _buildCard(context, formState);
    }

    // Otherwise, query the data source.
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: engine.queryDataSource(model.dataSource),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No data available'),
              ),
            ),
          );
        }

        // Show the first (most recent) record.
        final row = snapshot.data!.first;
        final data = row.map((k, v) => MapEntry(k, v?.toString() ?? ''));
        return _buildCard(context, data);
      },
    );
  }

  Widget _buildCard(BuildContext context, Map<String, String> data) {
    final theme = Theme.of(context);

    // Determine which fields to show and in what order.
    List<String> fieldNames;
    if (model.fields != null && model.fields!.isNotEmpty) {
      fieldNames = model.fields!;
    } else {
      // Show all fields except internal ones.
      fieldNames = data.keys
          .where((k) => !k.startsWith('_'))
          .toList();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: fieldNames.map((field) {
              final label = model.labels?[field] ?? _humanize(field);
              final value = data[field] ?? '';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _labelWidth,
                      child: Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        value,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  /// Converts a camelCase or snake_case field name to a human-readable label.
  static String _humanize(String name) {
    // Insert spaces before uppercase letters (camelCase).
    final spaced = name.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    // Replace underscores and capitalize first letter.
    final words = spaced.replaceAll('_', ' ').trim();
    if (words.isEmpty) return name;
    return words[0].toUpperCase() + words.substring(1);
  }
}
