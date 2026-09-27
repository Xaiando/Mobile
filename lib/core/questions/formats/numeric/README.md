# Numeric quantity contract

Q4 reuses canonical quantity values and the existing single-item question, settings and review pipelines. NumericQuestion extends PresentedQuestion. NumericFormat is objective, structured, forward-only, single generation and depth 2. It has no distractors or additional review state.

A quantity needs a finite minimum, an optional finite maximum at least as large, and a nonempty unit. A missing maximum means a scalar equal to the minimum. The item must be unsuperseded, its relation and both nodes current on the device-local date, and its subject/relation must have exactly one current object. That uniqueness check includes structural relations without an authored card. Invalid scope parameters or quantity metadata suppress generation and fail presentation.

Template parameters:

- exact_tolerance: finite nonnegative Good-band width on either side of the canonical band; default 0.
- tolerance: finite nonnegative TOTAL outer width on either side, at least exact_tolerance; default 0. It is not added to exact_tolerance.
- scope_node_ids: optional nonempty list of distinct subject IDs.

All regulatoryRelationTypes require both widths to be zero. MIN_AGEING and MIN_WOOD_AGEING ask the exact lower endpoint, even if a quantity also records an upper value. A longer permitted ageing duration does not answer the minimum. These questions never accept intervals.

For nonlegal genuine intervals, a scalar inside the exact band or an ordered interval wholly inside it earns Good. An answer wholly inside the outer band but outside the exact band earns Hard; other answers earn Again. A scalar quantity does not accept an interval answer. NumericOutcome is exact, near or wrong; grade writes exactly one ItemGrade.

NumericAnswer.scalar and NumericAnswer.interval carry explicitly declared units. NumericAnswer.tryParse returns null for malformed input. Syntax uses dot decimals and finite, representable scientific values; commas, expressions, nonfinite values, underflow to a false zero, incompatible unit suffixes and reversed ranges are rejected. ASCII/Unicode minus and hyphen/en-dash/em-dash or “to” interval separators are supported. A missing suffix uses defaultUnit. Explicit aliases are narrow; unknown unit spellings must match the target exactly. Only Celsius/Fahrenheit convert across units.

Temperature preference comes from LearnerSettings.current().temperatureUnit. Both temperature presentation domains and their outer endpoints must remain finite before generation. Grading transforms canonical band endpoints into the submitted supported unit and compares there directly. It does not convert the answer back to decide a grade and applies no grading epsilon. Display formatting does not round accepted boundaries.

Conversion and tolerance addition use the semantic decimal values of finite doubles, exact integer fractions and one final double parse. This keeps 16.4 °C equivalent to 61.52 °F and includes 16.6 within a 16.4 ± 0.2 band. Raw input must retain its decimal value after parsing: equivalent spellings such as 38.0 and 3.8e1 are accepted, while 38.0000000000000001 is rejected rather than silently becoming an exact legal answer of 38. Work and input length are bounded; finite large conversions avoid intermediate overflow.

The review payload records raw text when supplied, submitted scalar/interval and unit, canonical and preferred-display answer representations, canonical/display target bounds, tolerance metadata, outcome, metadata validity and seed. Nonfinite constructor inputs are recorded as null rather than unsafe JSON NaN/Infinity. Target values and displayAnswer are feedback only; views must not reveal them before submission.

Public DTOs and unit helpers are exported from numeric_format.dart. This note documents implementation behavior; it adds no curriculum facts or temperature recommendation.
