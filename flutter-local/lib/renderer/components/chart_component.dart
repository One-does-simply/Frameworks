import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/app_engine.dart';
import '../../models/ods_component.dart';

/// Renders an [OdsChartComponent] as a bar, line, or pie chart using fl_chart.
///
/// ODS Spec: The chart component references a GET data source and maps
/// `labelField` to categories and `valueField` to numeric values.
/// Supports three chart types: bar, line, and pie.
///
/// ODS Ethos: The builder writes a few lines of JSON and gets a real chart.
/// No charting library knowledge needed. The framework picks colors, handles
/// layout, and makes it look good automatically.
class OdsChartWidget extends StatelessWidget {
  final OdsChartComponent model;

  const OdsChartWidget({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AppEngine>();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: engine.queryDataSource(model.dataSource),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final rows = snapshot.data ?? [];
          if (rows.isEmpty) {
            return const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No data for chart.', style: TextStyle(color: Colors.grey)),
              ),
            );
          }

          // Aggregate data: group by labelField using the chosen aggregate mode.
          // Cap rows to prevent excessive memory use with large datasets.
          final cappedRows = rows.length > 10000 ? rows.sublist(0, 10000) : rows;
          final sums = <String, double>{};
          final counts = <String, int>{};
          for (final row in cappedRows) {
            final label = row[model.labelField]?.toString() ?? 'Unknown';
            final value = double.tryParse(row[model.valueField]?.toString() ?? '') ?? 0;
            sums[label] = (sums[label] ?? 0) + value;
            counts[label] = (counts[label] ?? 0) + 1;
          }

          final labels = sums.keys.toList();
          final List<double> values;
          switch (model.aggregate) {
            case 'count':
              values = labels.map((l) => counts[l]!.toDouble()).toList();
            case 'avg':
              values = labels.map((l) => counts[l]! > 0 ? sums[l]! / counts[l]! : 0.0).toList();
            case 'sum':
            default:
              values = sums.values.toList();
          }

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (model.title != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        model.title!,
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  SizedBox(
                    height: 250,
                    child: _buildChart(context, labels, values),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChart(BuildContext context, List<String> labels, List<double> values) {
    switch (model.chartType) {
      case 'line':
        return _buildLineChart(context, labels, values);
      case 'pie':
        return _buildPieChart(context, labels, values);
      case 'bar':
      default:
        return _buildBarChart(context, labels, values);
    }
  }

  // ---------------------------------------------------------------------------
  // Bar chart
  // ---------------------------------------------------------------------------

  Widget _buildBarChart(BuildContext context, List<String> labels, List<double> values) {
    final colors = _generateColors(labels.length, context);
    final maxVal = values.fold<double>(0, (a, b) => math.max(a, b));

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxVal * 1.2,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${labels[group.x]}\n${rod.toY.toStringAsFixed(rod.toY == rod.toY.roundToDouble() ? 0 : 1)}',
                const TextStyle(color: Colors.white, fontSize: 12),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    labels[idx].length > 10 ? '${labels[idx].substring(0, 10)}…' : labels[idx],
                    style: const TextStyle(fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                );
              },
              reservedSize: 32,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 11),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(labels.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: values[i],
                color: colors[i],
                width: 20,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          );
        }),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Line chart
  // ---------------------------------------------------------------------------

  Widget _buildLineChart(BuildContext context, List<String> labels, List<double> values) {
    final color = Theme.of(context).colorScheme.primary;
    final maxVal = values.fold<double>(0, (a, b) => math.max(a, b));

    return LineChart(
      LineChartData(
        maxY: maxVal * 1.2,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final idx = spot.x.toInt();
                final label = idx >= 0 && idx < labels.length ? labels[idx] : '';
                return LineTooltipItem(
                  '$label\n${spot.y.toStringAsFixed(spot.y == spot.y.roundToDouble() ? 0 : 1)}',
                  const TextStyle(color: Colors.white, fontSize: 12),
                );
              }).toList();
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= labels.length || value != value.roundToDouble()) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    labels[idx].length > 10 ? '${labels[idx].substring(0, 10)}…' : labels[idx],
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              },
              reservedSize: 32,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 11),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(values.length, (i) => FlSpot(i.toDouble(), values[i])),
            isCurved: true,
            color: color,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: color.withAlpha(40),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pie chart
  // ---------------------------------------------------------------------------

  Widget _buildPieChart(BuildContext context, List<String> labels, List<double> values) {
    final colors = _generateColors(labels.length, context);
    final total = values.fold<double>(0, (a, b) => a + b);

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: List.generate(labels.length, (i) {
                final percentage = total > 0 ? (values[i] / total * 100) : 0;
                return PieChartSectionData(
                  color: colors[i],
                  value: values[i],
                  title: '${percentage.toStringAsFixed(0)}%',
                  titleStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  radius: 60,
                );
              }),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(labels.length, (i) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: colors[i],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        labels[i],
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Color generation
  // ---------------------------------------------------------------------------

  List<Color> _generateColors(int count, BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    if (count <= 1) return [primary];
    // Generate a spread of hues starting from the primary color.
    final baseHsl = HSLColor.fromColor(primary);
    return List.generate(count, (i) {
      final hue = (baseHsl.hue + (i * 360 / count)) % 360;
      return HSLColor.fromAHSL(1.0, hue, 0.65, 0.55).toColor();
    });
  }
}
