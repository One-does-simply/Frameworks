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
  static final _ternaryPattern = RegExp(
    r"^(.+?)\s*==\s*(.+?)\s*\?\s*'([^']*)'\s*:\s*'([^']*)'\s*$",
  );

  /// Evaluates an expression given the current form field values.
  ///
  /// Returns the computed string value. Returns empty string on failure.
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

    // Try math evaluation if it looks numeric.
    if (_looksNumeric(substituted)) {
      try {
        return FormulaEvaluator.evaluate(expression, 'number', values);
      } catch (_) {
        // Fall through to string interpolation.
      }
    }

    // Default: return the substituted string (string interpolation).
    return substituted;
  }

  /// Quick heuristic: does the string look like a math expression?
  static bool _looksNumeric(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return false;
    // Contains at least one digit and only math-related characters.
    return RegExp(r'^[\d\s\+\-\*\/\(\)\.]+$').hasMatch(trimmed);
  }
}
