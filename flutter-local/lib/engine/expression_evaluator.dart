import 'formula_evaluator.dart';

/// Evaluates expressions for computed fields on submit/update actions.
///
/// Extends the concept in [FormulaEvaluator] with additional capabilities:
///   - Ternary comparison: `{a} == {b} ? 'yes' : 'no'`
///   - Magic values: `NOW` (current ISO datetime)
///   - Math expressions: delegated to [FormulaEvaluator]
///   - String interpolation: `{firstName} {lastName}`
class ExpressionEvaluator {
  static final _fieldPattern = RegExp(r'\{(\w+)\}');

  /// Pattern for ternary comparison expressions.
  /// Matches: `<left> == <right> ? '<trueVal>' : '<falseVal>'`
  ///
  /// Uses possessive-style bounded groups to avoid catastrophic backtracking:
  /// left/right are non-whitespace tokens (no greedy `.+?` over arbitrary input).
  static final _ternaryPattern = RegExp(
    r"^(\S+)\s*==\s*(\S+)\s*\?\s*'([^']*)'\s*:\s*'([^']*)'\s*$",
  );

  /// Evaluates an expression given the current form field values.
  ///
  /// Resolves `{fieldName}` references from [values], then attempts (in order):
  ///   1. Magic value `NOW` → current ISO datetime
  ///   2. Ternary comparison → `left == right ? 'a' : 'b'`
  ///   3. Numeric math → delegated to [FormulaEvaluator]
  ///   4. String interpolation → returns the substituted string as-is
  ///
  /// Returns the computed string value, or the raw substituted string on failure.
  static String evaluate(String expression, Map<String, String> values) {
    // Magic value: NOW → current ISO datetime.
    if (expression.trim().toUpperCase() == 'NOW') {
      return DateTime.now().toIso8601String();
    }

    // Substitute field references first.
    final substituted = expression.replaceAllMapped(_fieldPattern, (match) {
      return values[match.group(1)!] ?? '';
    });

    // Check for ternary comparison pattern.
    final ternaryMatch = _ternaryPattern.firstMatch(substituted);
    if (ternaryMatch != null) {
      final left = ternaryMatch.group(1)!.trim();
      final right = ternaryMatch.group(2)!.trim();
      final trueVal = ternaryMatch.group(3)!;
      final falseVal = ternaryMatch.group(4)!;
      return left == right ? trueVal : falseVal;
    }

    // Try math evaluation if it looks numeric. Pass the *substituted* string
    // so FormulaEvaluator sees concrete numbers, not `{field}` placeholders.
    if (_looksNumeric(substituted)) {
      try {
        // FormulaEvaluator.evaluate expects {field} refs + values map, but
        // since we already substituted, pass the substituted string with an
        // empty values map so it parses the literal numbers directly.
        return FormulaEvaluator.evaluate(substituted, 'number', {});
      } catch (_) {
        // Fall through to string interpolation.
      }
    }

    // Default: return the substituted string (string interpolation).
    return substituted;
  }

  /// Evaluates an expression and returns a boolean result.
  ///
  /// Used for expression-based visibility (`visible` property on components).
  /// Supports:
  ///   - `{field} == 'value'` → equality check
  ///   - `{field} != 'value'` → inequality check
  ///   - `{field}` → truthy check (non-null, non-empty, not "false", not "0")
  ///   - `!{field}` → negated truthy check
  static bool evaluateBool(String expression, Map<String, String> values) {
    final expr = expression.trim();
    if (expr.isEmpty) return true;

    // Substitute field references.
    final substituted = expr.replaceAllMapped(_fieldPattern, (match) {
      return values[match.group(1)!] ?? '';
    });

    // Equality: left == 'value' or left == right
    // Uses [^=!]+ instead of .+? to avoid backtracking across == or != tokens.
    final eqMatch = RegExp(r"^([^=!]+?)\s*==\s*'?([^']*)'?\s*$").firstMatch(substituted);
    if (eqMatch != null) {
      return eqMatch.group(1)!.trim() == eqMatch.group(2)!.trim();
    }

    // Inequality: left != 'value' or left != right
    final neqMatch = RegExp(r"^([^=!]+?)\s*!=\s*'?([^']*)'?\s*$").firstMatch(substituted);
    if (neqMatch != null) {
      return neqMatch.group(1)!.trim() != neqMatch.group(2)!.trim();
    }

    // Negation: !value
    if (substituted.startsWith('!')) {
      return !_isTruthy(substituted.substring(1).trim());
    }

    // Truthy check.
    return _isTruthy(substituted);
  }

  /// Returns true if a value is truthy (non-null, non-empty, not "false", not "0").
  static bool _isTruthy(String value) {
    if (value.isEmpty) return false;
    if (value == 'false') return false;
    if (value == '0') return false;
    return true;
  }

  /// Quick heuristic: does the string look like a math expression?
  static bool _looksNumeric(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return false;
    // Contains at least one digit and only math-related characters.
    return RegExp(r'^[\d\s\+\-\*\/\(\)\.]+$').hasMatch(trimmed);
  }
}
