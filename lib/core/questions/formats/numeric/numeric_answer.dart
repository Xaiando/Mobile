/// Canonical tokens for the small set of explicitly supported unit aliases.
/// Other units retain their exact spelling; they are never guessed or converted.
String canonicalUnitOf(String unit) {
  final text = unit.trim().replaceAll(RegExp(r'\s+'), ' ');
  return switch (text.toLowerCase()) {
    'c' ||
    '°c' ||
    '℃' ||
    'celsius' ||
    'deg c' ||
    'degc' ||
    'degree c' ||
    'degrees c' ||
    'degree celsius' ||
    'degrees celsius' => '°C',
    'f' ||
    '°f' ||
    '℉' ||
    'fahrenheit' ||
    'deg f' ||
    'degf' ||
    'degree f' ||
    'degrees f' ||
    'degree fahrenheit' ||
    'degrees fahrenheit' => '°F',
    'month' || 'months' => 'month',
    'year' || 'years' => 'year',
    '%' || 'percent' || 'per cent' => '%',
    'ha' || 'hectare' || 'hectares' => 'ha',
    'm' || 'metre' || 'metres' || 'meter' || 'meters' => 'm',
    _ => text,
  };
}

bool unitMatches(String first, String second) =>
    canonicalUnitOf(first).isNotEmpty &&
    canonicalUnitOf(first) == canonicalUnitOf(second);

bool _isTemperature(String unit) => const {'°C', '°F'}.contains(unit);

/// Finite double decimals are the authored/displayed values, rather than the
/// intermediate binary rounding errors of several arithmetic operations.
(BigInt, BigInt) _decimalRatio(double value) =>
    _decimalRatioText(value.toString());

(BigInt, BigInt) _decimalRatioText(String text) {
  final match = RegExp(r'^([+-]?)(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$')
      .firstMatch(text);
  if (match == null) {
    throw ArgumentError('Cannot represent a finite numeric decimal');
  }
  final integer = match.group(2)!;
  final fraction = match.group(3) ?? '';
  final digits = integer + fraction;
  if (digits.isEmpty) {
    throw ArgumentError('Numeric decimal has no digits');
  }
  // Zero has no exponent work, including a lexeme with a huge zero exponent.
  if (!RegExp(r'[1-9]').hasMatch(digits)) {
    return (BigInt.zero, BigInt.one);
  }
  final exponent = int.tryParse(match.group(4) ?? '0');
  // Source doubles have exponents -324..308. Raw input reaches this helper
  // only after its 256-character, finite and nonzero-underflow checks; 1024
  // bounds work beyond every supported nonzero decimal spelling.
  if (exponent == null || exponent.abs() > 1024) {
    throw ArgumentError('Numeric decimal exponent is unsupported');
  }
  final scale = fraction.length - exponent;
  var numerator = BigInt.parse(digits);
  if (match.group(1) == '-') {
    numerator = -numerator;
  }
  var denominator = BigInt.one;
  if (scale > 0) {
    denominator = BigInt.from(10).pow(scale);
  } else if (scale < 0) {
    numerator *= BigInt.from(10).pow(-scale);
  }
  return (numerator, denominator);
}

/// Rounds once through double.parse, with no acceptance-band epsilon.
/// The 750-place bound is conservative for finite IEEE doubles: shortest
/// decimals have at most 17 significant digits and exponents down to -324,
/// so source denominators are bounded by 10^340. After gcd normalization,
/// decimal offsets have that same bound; C/F adds at most a factor of 9.
/// Binary rounding midpoint denominators are bounded by 2^1075. A nonzero
/// distance to such a midpoint exceeds 10^-665, far above this truncation
/// error. Exact midpoint rationals terminate; remainder-zero exits early.
double _decimalResult(BigInt numerator, BigInt denominator) {
  if (numerator == BigInt.zero) {
    return 0;
  }
  final sign = numerator < BigInt.zero ? '-' : '';
  var absolute = numerator.abs();
  final common = absolute.gcd(denominator);
  absolute ~/= common;
  denominator ~/= common;
  final result = StringBuffer(sign);
  result.write(absolute ~/ denominator);
  var remainder = absolute.remainder(denominator);
  if (remainder != BigInt.zero) {
    result.write('.');
    for (var index = 0; index < 750 && remainder != BigInt.zero; index++) {
      remainder *= BigInt.from(10);
      result.write(remainder ~/ denominator);
      remainder %= denominator;
    }
  }
  return double.parse(result.toString());
}

double _decimalTemperature(double value, {required bool fromCelsius}) {
  final (numerator, denominator) = _decimalRatio(value);
  return fromCelsius
      ? _decimalResult(
          numerator * BigInt.from(9) + denominator * BigInt.from(160),
          denominator * BigInt.from(5),
        )
      : _decimalResult(
          (numerator - denominator * BigInt.from(32)) * BigInt.from(5),
          denominator * BigInt.from(9),
        );
}

/// Adds an authored decimal width once, without a grading epsilon.
/// A zero width preserves the exact original double, including signed zero.
double numericOffset(double value, double offset) {
  if (!value.isFinite || !offset.isFinite) {
    throw ArgumentError('Numeric offsets require finite values');
  }
  if (offset == 0) {
    return value;
  }
  final (firstNumerator, firstDenominator) = _decimalRatio(value);
  final (secondNumerator, secondDenominator) = _decimalRatio(offset);
  final result = _decimalResult(
    firstNumerator * secondDenominator + secondNumerator * firstDenominator,
    firstDenominator * secondDenominator,
  );
  if (!result.isFinite) {
    throw ArgumentError('Numeric offset overflowed');
  }
  return result;
}

/// Decimal precision must survive parsing semantically, not lexically:
/// 0.10 and 3.8e1 are equivalent spellings; 38.0000000000000001 is not 38.
bool _sameDecimalLexeme(String text, double value) {
  if (value == 0) {
    // The caller already rejected a nonzero mantissa that underflowed to zero.
    return true;
  }
  try {
    final (inputNumerator, inputDenominator) = _decimalRatioText(text);
    final (storedNumerator, storedDenominator) = _decimalRatio(value);
    return inputNumerator * storedDenominator ==
        storedNumerator * inputDenominator;
  } on ArgumentError {
    return false;
  }
}

/// Converts only Celsius/Fahrenheit. Unsupported units, nonfinite inputs and
/// overflowing results throw instead of producing a value that could be graded.
double convertTemperature(
  double value, {
  required String fromUnit,
  required String toUnit,
}) {
  final from = canonicalUnitOf(fromUnit);
  final to = canonicalUnitOf(toUnit);
  if (!value.isFinite || !_isTemperature(from) || !_isTemperature(to)) {
    throw ArgumentError('Temperature conversion requires finite C/F values');
  }
  final converted = from == to
      ? value
      : _decimalTemperature(value, fromCelsius: from == '°C');
  if (!converted.isFinite) {
    throw ArgumentError('Temperature conversion overflowed');
  }
  return converted;
}

/// The only cross-unit conversion is C/F; identical supported or exact
/// unknown-unit tokens retain their value.
double numericValueInUnit(
  double value, {
  required String fromUnit,
  required String toUnit,
}) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, 'value', 'must be finite');
  }
  if (unitMatches(fromUnit, toUnit)) {
    return value;
  }
  return convertTemperature(value, fromUnit: fromUnit, toUnit: toUnit);
}

/// Finite numeric text without integer ".0"; no rounding expands a grade band.
String formatNumericValue(double value) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, 'value', 'must be finite');
  }
  if (value == 0) {
    return '0';
  }
  final text = value.toString();
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// A submitted scalar or ordered interval, in its explicitly declared unit.
/// Constructors permit malformed programmatic values so grading can fail
/// closed with Again, while [tryParse] rejects them before UI submission.
final class NumericAnswer {
  const NumericAnswer.scalar(double value, {required this.unit})
    : minimum = value,
      maximum = null;

  const NumericAnswer.interval(
    this.minimum,
    double this.maximum, {
    required this.unit,
  });

  final double minimum;
  final double? maximum;
  final String unit;

  bool get isInterval => maximum != null;
  bool get isValid =>
      minimum.isFinite &&
      canonicalUnitOf(unit).isNotEmpty &&
      (maximum == null || (maximum!.isFinite && maximum! >= minimum));

  static const _number = r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?';
  static final _input = RegExp(
    '^($_number)(?:\\s*(?:-|–|—|to)\\s*($_number))?\\s*(.*?)\$',
    caseSensitive: false,
  );

  /// Strict dot-decimal/scientific syntax. Comma grouping/decimals, expressions,
  /// NaN/Infinity and incompatible suffixes are rejected. A suffix may name the
  /// default unit or its C/F counterpart. A missing suffix uses [defaultUnit].
  static NumericAnswer? tryParse(String text, {required String defaultUnit}) {
    if (text.length > 256 ||
        text.contains(',') ||
        canonicalUnitOf(defaultUnit).isEmpty) {
      return null;
    }
    final match = _input.firstMatch(text.trim().replaceAll('−', '-'));
    if (match == null) {
      return null;
    }
    final minimum = double.tryParse(match.group(1)!);
    final upperText = match.group(2);
    final maximum = upperText == null ? null : double.tryParse(upperText);
    bool representable(String number, double value) =>
        value != 0 ||
        !RegExp(r'[1-9]').hasMatch(number.split(RegExp('[eE]')).first);
    final suffix = match.group(3)!.trim();
    final unit = canonicalUnitOf(suffix.isEmpty ? defaultUnit : suffix);
    final target = canonicalUnitOf(defaultUnit);
    if (minimum == null ||
        !minimum.isFinite ||
        !representable(match.group(1)!, minimum) ||
        (upperText != null && (maximum == null || !maximum.isFinite)) ||
        (upperText != null &&
            maximum != null &&
            !representable(upperText, maximum)) ||
        !(unitMatches(unit, target) ||
            (_isTemperature(unit) && _isTemperature(target)))) {
      return null;
    }
    if (!_sameDecimalLexeme(match.group(1)!, minimum) ||
        (upperText != null &&
            maximum != null &&
            !_sameDecimalLexeme(upperText, maximum))) {
      return null;
    }
    final answer = maximum == null
        ? NumericAnswer.scalar(minimum, unit: unit)
        : NumericAnswer.interval(minimum, maximum, unit: unit);
    return answer.isValid ? answer : null;
  }

  /// Nonfinite constructor inputs are recorded as null, never unsafe JSON.
  Map<String, Object?> toJson() => {
    'minimum': minimum.isFinite ? minimum : null,
    'maximum': maximum?.isFinite == true ? maximum : null,
    'unit': unit,
    'is_interval': isInterval,
    'valid': isValid,
  };
}
