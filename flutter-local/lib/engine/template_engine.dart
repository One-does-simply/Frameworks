/// JSON-e subset engine for ODS templates.
///
/// Implements the three JSON-e operators needed for Quick Build templates:
///   - `${expr}` string interpolation — replaces variable references in strings
///   - `$if`/`then`/`else` — conditionally includes or omits values
///   - `$map`/`each(v)` — iterates an array to produce a list of values
///   - `$eval` — evaluates an expression and returns the raw value
///   - `$flatten` — flattens nested arrays one level
///
/// Templates are valid JSON-e. Frameworks with a full JSON-e library can skip
/// this engine entirely. This subset covers the operators used by ODS templates
/// while keeping the implementation small and dependency-free.
class TemplateEngine {
  /// Renders a JSON-e template with the given context.
  ///
  /// [template] is the parsed JSON value (Map, List, String, num, bool, null).
  /// [context] is the variable bindings from question answers.
  /// Returns the rendered JSON value ready to be used as an ODS spec.
  static dynamic render(dynamic template, Map<String, dynamic> context) {
    if (template is String) {
      return _interpolateString(template, context);
    }
    if (template is List) {
      return template
          .map((item) => render(item, context))
          .where((item) => item != _removed)
          .toList();
    }
    if (template is Map<String, dynamic>) {
      return _renderObject(template, context);
    }
    // Primitives pass through.
    return template;
  }

  /// Processes a JSON object, handling $if, $map, $eval, $flatten operators.
  static dynamic _renderObject(
    Map<String, dynamic> obj,
    Map<String, dynamic> context,
  ) {
    // --- $if / then / else ---
    if (obj.containsKey('\$if')) {
      final condition = obj['\$if'] as String;
      final result = _evaluateCondition(condition, context);
      if (result) {
        final thenBranch = obj['then'];
        return thenBranch == null ? _removed : render(thenBranch, context);
      } else {
        final elseBranch = obj['else'];
        return elseBranch == null ? _removed : render(elseBranch, context);
      }
    }

    // --- $eval ---
    if (obj.containsKey('\$eval')) {
      final expr = obj['\$eval'] as String;
      return _evaluateExpression(expr, context);
    }

    // --- $flatten ---
    if (obj.containsKey('\$flatten')) {
      final inner = render(obj['\$flatten'], context);
      if (inner is List) {
        final result = <dynamic>[];
        for (final item in inner) {
          if (item is List) {
            result.addAll(item);
          } else if (item != _removed) {
            result.add(item);
          }
        }
        return result;
      }
      return inner;
    }

    // --- $map / each(var) ---
    if (obj.containsKey('\$map')) {
      return _renderMap(obj, context);
    }

    // --- Plain object: render each value recursively ---
    final result = <String, dynamic>{};
    for (final entry in obj.entries) {
      final rendered = render(entry.value, context);
      if (rendered != _removed) {
        result[entry.key] = rendered;
      }
    }
    return result;
  }

  /// Handles `$map` + `each(varName)` — iterates over an array from context.
  static dynamic _renderMap(
    Map<String, dynamic> obj,
    Map<String, dynamic> context,
  ) {
    final sourceExpr = obj['\$map'] as String;
    final source = _evaluateExpression(sourceExpr, context);
    if (source is! List) return [];

    // Find the each(varName) or each(varName, indexName) key.
    String? varName;
    String? indexName;
    dynamic itemTemplate;
    for (final key in obj.keys) {
      final match = _eachPattern.firstMatch(key);
      if (match != null) {
        varName = match.group(1)!;
        indexName = match.group(2); // optional second capture group
        itemTemplate = obj[key];
        break;
      }
    }
    if (varName == null || itemTemplate == null) return [];

    final results = <dynamic>[];
    for (int i = 0; i < source.length; i++) {
      final itemContext = Map<String, dynamic>.from(context);
      itemContext[varName] = source[i];
      // Expose the index under both the explicit name (if given) and the
      // legacy implicit name so templates using either convention work.
      itemContext['${varName}Index'] = i;
      if (indexName != null) {
        itemContext[indexName] = i;
      }
      final rendered = render(itemTemplate, itemContext);
      if (rendered != _removed) {
        results.add(rendered);
      }
    }
    return results;
  }

  static final _eachPattern = RegExp(r'^each\((\w+)(?:,\s*(\w+))?\)$');

  /// Interpolates `${expr}` references in a string.
  /// If the entire string is a single `${expr}`, returns the raw value
  /// (preserving type — e.g., a list stays a list).
  static dynamic _interpolateString(
    String template,
    Map<String, dynamic> context,
  ) {
    // Whole-string expression: return raw value to preserve type.
    final wholeMatch = _wholeExprPattern.firstMatch(template);
    if (wholeMatch != null) {
      return _evaluateExpression(wholeMatch.group(1)!, context);
    }

    // Partial interpolation: replace each ${...} with its string value.
    return template.replaceAllMapped(_exprPattern, (match) {
      final expr = match.group(1)!;
      final value = _evaluateExpression(expr, context);
      return value?.toString() ?? '';
    });
  }

  static final _wholeExprPattern = RegExp(r'^\$\{(.+)\}$');
  static final _exprPattern = RegExp(r'\$\{(.+?)\}');

  /// Evaluates a simple expression against context.
  /// Supports dotted paths (a.b.c) and indexed access (a[0]).
  static dynamic _evaluateExpression(
    String expr,
    Map<String, dynamic> context,
  ) {
    expr = expr.trim();

    // String literal: 'hello' or "hello"
    if ((expr.startsWith("'") && expr.endsWith("'")) ||
        (expr.startsWith('"') && expr.endsWith('"'))) {
      return expr.substring(1, expr.length - 1);
    }

    // Numeric literal
    final asNum = num.tryParse(expr);
    if (asNum != null) return asNum;

    // Boolean literal
    if (expr == 'true') return true;
    if (expr == 'false') return false;

    // Navigate dotted/indexed path: e.g., "field.name" or "fields[0].name"
    return _resolvePath(expr, context);
  }

  /// Resolves a dotted/indexed path like "field.options" or "fields[0].name".
  static dynamic _resolvePath(String path, Map<String, dynamic> context) {
    // Tokenize: split on dots, but also handle bracket indexing.
    final segments = <_PathSegment>[];
    final buffer = StringBuffer();

    for (int i = 0; i < path.length; i++) {
      final ch = path[i];
      if (ch == '.') {
        if (buffer.isNotEmpty) {
          segments.add(_PathSegment.field(buffer.toString()));
          buffer.clear();
        }
      } else if (ch == '[') {
        if (buffer.isNotEmpty) {
          segments.add(_PathSegment.field(buffer.toString()));
          buffer.clear();
        }
        // Read until ]
        i++;
        while (i < path.length && path[i] != ']') {
          buffer.write(path[i]);
          i++;
        }
        final index = int.tryParse(buffer.toString());
        if (index != null) {
          segments.add(_PathSegment.index(index));
        } else {
          segments.add(_PathSegment.field(buffer.toString()));
        }
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    if (buffer.isNotEmpty) {
      segments.add(_PathSegment.field(buffer.toString()));
    }

    dynamic current = context;
    for (final segment in segments) {
      if (current == null) return null;
      if (segment.isIndex) {
        if (current is List && segment.index! < current.length) {
          current = current[segment.index!];
        } else {
          return null;
        }
      } else {
        if (current is Map) {
          current = current[segment.name];
        } else {
          return null;
        }
      }
    }
    return current;
  }

  /// Evaluates a boolean condition string.
  /// Supports: `varName`, `!varName`, `a == b`, `a != b`, `a == 'literal'`,
  /// `a && b`, `a || b`.
  static bool _evaluateCondition(
    String condition,
    Map<String, dynamic> context,
  ) {
    condition = condition.trim();

    // Logical AND: split on && first (lowest precedence after ||).
    // Use indexOf to avoid splitting string literals containing &&.
    final andIndex = _findLogicalOp(condition, '&&');
    if (andIndex >= 0) {
      final left = condition.substring(0, andIndex).trim();
      final right = condition.substring(andIndex + 2).trim();
      return _evaluateCondition(left, context) &&
          _evaluateCondition(right, context);
    }

    // Logical OR.
    final orIndex = _findLogicalOp(condition, '||');
    if (orIndex >= 0) {
      final left = condition.substring(0, orIndex).trim();
      final right = condition.substring(orIndex + 2).trim();
      return _evaluateCondition(left, context) ||
          _evaluateCondition(right, context);
    }

    // Negation: !expr
    if (condition.startsWith('!')) {
      return !_evaluateCondition(condition.substring(1), context);
    }

    // Equality: a == b
    if (condition.contains('==')) {
      final parts = condition.split('==').map((s) => s.trim()).toList();
      if (parts.length == 2) {
        final left = _evaluateExpression(parts[0], context);
        final right = _evaluateExpression(parts[1], context);
        return left.toString() == right.toString();
      }
    }

    // Inequality: a != b
    if (condition.contains('!=')) {
      final parts = condition.split('!=').map((s) => s.trim()).toList();
      if (parts.length == 2) {
        final left = _evaluateExpression(parts[0], context);
        final right = _evaluateExpression(parts[1], context);
        return left.toString() != right.toString();
      }
    }

    // Truthy check: just a variable name
    final value = _evaluateExpression(condition, context);
    if (value == null) return false;
    if (value is bool) return value;
    if (value is String) return value.isNotEmpty;
    if (value is num) return value != 0;
    if (value is List) return value.isNotEmpty;
    return true;
  }

  /// Finds the index of a logical operator (`&&` or `||`) outside of string
  /// literals. Returns -1 if not found.
  static int _findLogicalOp(String condition, String op) {
    var inSingle = false;
    var inDouble = false;
    for (var i = 0; i < condition.length - 1; i++) {
      final ch = condition[i];
      if (ch == "'" && !inDouble) {
        inSingle = !inSingle;
      } else if (ch == '"' && !inSingle) {
        inDouble = !inDouble;
      } else if (!inSingle && !inDouble) {
        if (condition.substring(i, i + 2) == op) {
          return i;
        }
      }
    }
    return -1;
  }

  /// Sentinel value indicating a conditionally removed element.
  static const _removed = _Removed();
}

/// Sentinel class for removed elements (from failed $if with no else).
class _Removed {
  const _Removed();
}

/// A segment in a dotted/indexed path.
class _PathSegment {
  final String? name;
  final int? index;
  bool get isIndex => index != null;

  const _PathSegment.field(this.name) : index = null;
  const _PathSegment.index(this.index) : name = null;
}
