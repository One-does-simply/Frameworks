import 'package:flutter/material.dart';

import '../../models/ods_component.dart';
import '../page_renderer.dart';
import '../style_resolver.dart';

/// Renders an [OdsTabsComponent] as a tabbed layout using Material TabBar.
///
/// Each tab has its own content array of components, rendered using the
/// same dispatch logic as [PageRenderer].
class OdsTabsWidget extends StatelessWidget {
  /// Default height for the tab content area. Provides enough space for
  /// lists, charts, and forms within a scrollable page.
  static const double _tabContentHeight = 400;

  final OdsTabsComponent model;
  final StyleResolver styleResolver;

  const OdsTabsWidget({
    super.key,
    required this.model,
    this.styleResolver = const StyleResolver(),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DefaultTabController(
        length: model.tabs.length,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabBar(
              isScrollable: model.tabs.length > 3,
              tabs: model.tabs
                  .asMap()
                  .entries
                  .map((e) => Tab(key: ValueKey(e.key), text: e.value.label))
                  .toList(),
            ),
            SizedBox(
              // Give the tab content a reasonable height. If the content is
              // a list or chart, it needs space. Using ConstrainedBox with a
              // minimum height works well in a scrollable page.
              height: _tabContentHeight,
              child: TabBarView(
                children: model.tabs.map((tab) {
                  return ListView(
                    padding: const EdgeInsets.only(top: 12),
                    children: tab.content
                        .map((c) => PageRenderer.renderComponent(c, styleResolver))
                        .toList(),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
