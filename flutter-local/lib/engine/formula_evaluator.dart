/// Evaluates formula expressions for computed fields.
///
/// ODS Spec: Computed fields use `{fieldName}` placeholders to reference
/// other fields. For number-type fields, the result is evaluated as a math
/// expression (supports +, -, *, /, parentheses). For text-type fields,
/// placeholders are simply replaced with their values (string interpolation).
class FormulaEvaluator {
  static final _fieldPattern = RegExp(r'\{(\w+)\}');

  /// Returns the list of field names referenced in a formula.
  static List<String> dependencies(String formula) {
    return _fieldPattern
        .allMatches(formula)
        .map((m) => m.group(1)!)
        .toSet()
        .toList();
  }

  /// Evaluates a formula given field values.
  ///
  /// For [fieldType] "number", substitutes values and evaluates the math
  /// expression. For all other types, performs string interpolation.
  /// Returns an empty string if any referenced field is missing or if
  /// evaluation fails.
  static String evaluate(
    String formula,
    String fieldType,
    Map<String, String?> values,
  ) {
    // Check that all referenced fields have values.
    final refs = _fieldPattern.allMatches(formula);
    for (final match in refs) {
      final name = match.group(1)!;
      final val = values[name];
      if (val == null || val.isEmpty) return '';
    }

    // Substitute field references with their values.
    final substituted = formula.replaceAllMapped(_fieldPattern, (match) {
      return values[match.group(1)!] ?? '';
    });

    if (fieldType == 'number') {
      try {
        final result = _evaluateMath(substituted);
        if (result == result.roundToDouble()) {
          return result.toInt().toString();
        }
        // Round to 2 decimal places for display.
        return result.toStringAsFixed(2);
      } catch (_) {
        return '';
      }
    }

    // For text and other types, return the interpolated string.
    return substituted;
  }

  // ---------------------------------------------------------------------------
  // Simple recursive-descent math evaluator for +, -, *, /, parentheses.
  // ---------------------------------------------------------------------------

  static double _evaluateMath(String expression) {
    final tokens = _tokenize(expression);
    final parser = _MathParser(tokens);
    final result = parser.parseExpression();
    if (parser._pos < tokens.length) {
      throw FormatException('Unexpected token: ${tokens[parser._pos]}');
    }
    return result;
  }

  /// Tokenizes a math expression string into numbers and operator characters.
  static List<String> _tokenize(String expr) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    for (var i = 0; i < expr.length; i++) {
      final ch = expr[i];
      if (ch == ' ') {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }
      if ('+-*/()'.contains(ch)) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        // Handle unary minus: at start, after '(', or after an operator.
        if (ch == '-' &&
            (tokens.isEmpty ||
                tokens.last == '(' ||
                '+-*/'.contains(tokens.last))) {
          buffer.write('-');
        } else {
          tokens.add(ch);
        }
      } else {
        buffer.write(ch);
      }
    }
    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
    }
    return tokens;
  }
}

/// Simple recursive-descent parser for math expressions.
///
/// Grammar:
///   expression = term (('+' | '-') term)*
///   term       = factor (('*' | '/') factor)*
///   factor     = NUMBER | '(' expression ')'
class _MathParser {
  final List<String> _tokens;
  int _pos = 0;

  _MathParser(this._tokens);

  String? _peek() => _pos < _tokens.length ? _tokens[_pos] : null;

  String _consume() {
    if (_pos >= _tokens.length) throw FormatException('Unexpected end of expression');
    return _tokens[_pos++];
  }

  double parseExpression() {
    var result = _parseTerm();
    while (_peek() == '+' || _peek() == '-') {
      final op = _consume();
      final right = _parseTerm();
      result = op == '+' ? result + right : result - right;
    }
    return result;
  }

  double _parseTerm() {
    var result = _parseFactor();
    while (_peek() == '*' || _peek() == '/') {
      final op = _consume();
      final right = _parseFactor();
      result = op == '*' ? result * right : result / right;
    }
    return result;
  }

  double _parseFactor() {
    if (_peek() == '(') {
      _consume(); // '('
      final result = parseExpression();
      if (_peek() != ')') throw FormatException('Expected closing parenthesis');
      _consume(); // ')'
      return result;
    }
    final token = _consume();
    final value = double.tryParse(token);
    if (value == null) throw FormatException('Expected number, got: $token');
    return value;
  }
}
