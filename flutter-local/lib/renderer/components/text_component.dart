import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';

import '../../engine/aggregate_evaluator.dart';
import '../../engine/app_engine.dart';
import '../../models/ods_component.dart';
import '../style_resolver.dart';

/// Renders an [OdsTextComponent] as a styled Text widget, or as Markdown
/// when the `format` property is set to 'markdown'.
///
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
    final textAlign = styleResolver.resolveTextAlign(model.styleHint);

    // Fast path: no aggregates → render directly.
    if (!AggregateEvaluator.hasAggregates(model.content)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _renderText(model.content, style, textAlign, context),
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
          return _renderText(text, style, textAlign, context);
        },
      ),
    );
  }

  Widget _renderText(String text, TextStyle? style, TextAlign textAlign, BuildContext context) {
    if (model.format == 'markdown') {
      return _MarkdownRenderer(
        text: text,
        baseStyle: style,
        crossAxisAlignment: styleResolver.resolveCrossAlignment(model.styleHint),
      );
    }
    return Text(text, style: style, textAlign: textAlign);
  }
}

/// Renders markdown text as Flutter widgets using the `markdown` package's AST.
class _MarkdownRenderer extends StatelessWidget {
  final String text;
  final TextStyle? baseStyle;
  final CrossAxisAlignment crossAxisAlignment;

  const _MarkdownRenderer({
    required this.text,
    this.baseStyle,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final document = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );
    final nodes = document.parse(text);
    final visitor = _FlutterNodeVisitor(context, baseStyle);
    final widgets = visitor.render(nodes);

    return Column(
      crossAxisAlignment: crossAxisAlignment,
      children: widgets,
    );
  }
}

/// Walks the markdown AST and produces Flutter widgets.
class _FlutterNodeVisitor {
  final BuildContext context;
  final TextStyle? baseStyle;

  _FlutterNodeVisitor(this.context, this.baseStyle);

  ThemeData get _theme => Theme.of(context);

  /// Renders a list of AST nodes into Flutter widgets.
  List<Widget> render(List<md.Node> nodes) {
    final widgets = <Widget>[];
    for (final node in nodes) {
      final widget = _renderBlock(node);
      if (widget != null) widgets.add(widget);
    }
    return widgets;
  }

  /// Renders a block-level node into a widget.
  Widget? _renderBlock(md.Node node) {
    if (node is md.Element) {
      switch (node.tag) {
        case 'h1':
          return Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: _buildRichText(node, _theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            )),
          );
        case 'h2':
          return Padding(
            padding: const EdgeInsets.only(bottom: 6, top: 4),
            child: _buildRichText(node, _theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            )),
          );
        case 'h3':
          return Padding(
            padding: const EdgeInsets.only(bottom: 4, top: 4),
            child: _buildRichText(node, _theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            )),
          );
        case 'h4':
        case 'h5':
        case 'h6':
          return Padding(
            padding: const EdgeInsets.only(bottom: 4, top: 2),
            child: _buildRichText(node, _theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            )),
          );
        case 'p':
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildRichText(node, baseStyle),
          );
        case 'ul':
          return _buildList(node, ordered: false);
        case 'ol':
          return _buildList(node, ordered: true);
        case 'blockquote':
          return _buildBlockquote(node);
        case 'pre':
          return _buildCodeBlock(node);
        case 'hr':
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(),
          );
        case 'table':
          return _buildTable(node);
        default:
          // Fall through to inline rendering for unknown block elements.
          return _buildRichText(node, baseStyle);
      }
    } else if (node is md.Text) {
      return Text(node.text, style: baseStyle);
    }
    return null;
  }

  /// Builds a RichText widget from an element's inline children.
  Widget _buildRichText(md.Element element, TextStyle? style) {
    final spans = _buildInlineSpans(element.children ?? [], style);
    return RichText(
      text: TextSpan(children: spans, style: style),
    );
  }

  /// Converts inline AST nodes to TextSpan children.
  List<InlineSpan> _buildInlineSpans(List<md.Node> nodes, TextStyle? parentStyle) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      if (node is md.Text) {
        spans.add(TextSpan(text: node.text, style: parentStyle));
      } else if (node is md.Element) {
        switch (node.tag) {
          case 'strong':
            final bold = (parentStyle ?? const TextStyle()).copyWith(fontWeight: FontWeight.w700);
            spans.addAll(_buildInlineSpans(node.children ?? [], bold));
          case 'em':
            final italic = (parentStyle ?? const TextStyle()).copyWith(fontStyle: FontStyle.italic);
            spans.addAll(_buildInlineSpans(node.children ?? [], italic));
          case 'del':
            final strikethrough = (parentStyle ?? const TextStyle()).copyWith(
              decoration: TextDecoration.lineThrough,
            );
            spans.addAll(_buildInlineSpans(node.children ?? [], strikethrough));
          case 'code':
            spans.add(TextSpan(
              text: node.textContent,
              style: TextStyle(
                fontFamily: 'monospace',
                backgroundColor: _theme.colorScheme.surfaceContainerHighest,
                fontSize: (parentStyle?.fontSize ?? 14) * 0.9,
              ),
            ));
          case 'a':
            // Safety: Only style as a link if the href uses a safe protocol.
            // This prevents javascript: or data: URI injection if tap handling
            // is ever added. Currently links are display-only (not tappable).
            final href = node.attributes['href'] ?? '';
            final isSafeLink = href.isEmpty ||
                href.startsWith('http://') ||
                href.startsWith('https://') ||
                href.startsWith('mailto:');
            final linkStyle = (parentStyle ?? const TextStyle()).copyWith(
              color: isSafeLink ? _theme.colorScheme.primary : _theme.colorScheme.error,
              decoration: TextDecoration.underline,
            );
            spans.add(TextSpan(text: node.textContent, style: linkStyle));
          case 'br':
            spans.add(const TextSpan(text: '\n'));
          case 'img':
            // Render image alt text as placeholder.
            final alt = node.attributes['alt'] ?? '';
            if (alt.isNotEmpty) {
              spans.add(TextSpan(
                text: '[$alt]',
                style: (parentStyle ?? const TextStyle()).copyWith(
                  fontStyle: FontStyle.italic,
                  color: _theme.colorScheme.outline,
                ),
              ));
            }
          default:
            // Recurse for unknown inline elements.
            spans.addAll(_buildInlineSpans(node.children ?? [], parentStyle));
        }
      }
    }
    return spans;
  }

  /// Builds an ordered or unordered list.
  Widget _buildList(md.Element element, {required bool ordered}) {
    final items = (element.children ?? []).whereType<md.Element>().toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;

          // Check for task list checkbox.
          final checkbox = _extractCheckbox(item);
          final bullet = checkbox != null
              ? (checkbox ? '\u2611 ' : '\u2610 ')
              : ordered
                  ? '${index + 1}. '
                  : '\u2022 ';

          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: ordered ? 28 : 20,
                  child: Text(bullet, style: baseStyle),
                ),
                Expanded(
                  child: _buildListItemContent(item),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Extracts checkbox state from a list item, if present.
  bool? _extractCheckbox(md.Element item) {
    final children = item.children;
    if (children == null || children.isEmpty) return null;
    final first = children.first;
    if (first is md.Element && first.tag == 'input') {
      return first.attributes['checked'] != null;
    }
    // Check inside a <p> wrapper.
    if (first is md.Element && first.tag == 'p') {
      final pChildren = first.children;
      if (pChildren != null && pChildren.isNotEmpty) {
        final pFirst = pChildren.first;
        if (pFirst is md.Element && pFirst.tag == 'input') {
          return pFirst.attributes['checked'] != null;
        }
      }
    }
    return null;
  }

  Widget _buildListItemContent(md.Element item) {
    final children = item.children ?? [];
    // If the item has a single paragraph, render inline. Otherwise render blocks.
    if (children.length == 1 && children.first is md.Element) {
      final child = children.first as md.Element;
      if (child.tag == 'p') {
        return _buildRichText(child, baseStyle);
      }
    }
    // Multi-block list item.
    final widgets = <Widget>[];
    for (final child in children) {
      final w = _renderBlock(child);
      if (w != null) widgets.add(w);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildBlockquote(md.Element element) {
    final innerWidgets = render(element.children ?? []);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: _theme.colorScheme.outline,
              width: 3,
            ),
          ),
        ),
        padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: innerWidgets,
        ),
      ),
    );
  }

  Widget _buildCodeBlock(md.Element element) {
    final code = element.textContent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          code,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: (baseStyle?.fontSize ?? 14) * 0.9,
          ),
        ),
      ),
    );
  }

  Widget _buildTable(md.Element element) {
    final rows = <TableRow>[];
    for (final section in (element.children ?? []).whereType<md.Element>()) {
      // section is thead or tbody
      for (final row in (section.children ?? []).whereType<md.Element>()) {
        final isHeader = section.tag == 'thead';
        final cells = (row.children ?? []).whereType<md.Element>().map((cell) {
          final style = isHeader
              ? (baseStyle ?? const TextStyle()).copyWith(fontWeight: FontWeight.w700)
              : baseStyle;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: _buildRichText(cell, style),
          );
        }).toList();
        rows.add(TableRow(children: cells));
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Table(
        border: TableBorder.all(
          color: _theme.colorScheme.outlineVariant,
          width: 1,
        ),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: rows,
      ),
    );
  }
}
