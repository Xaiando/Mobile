import 'package:clock/clock.dart';

import '../database/app_database.dart';
import '../time/utc_clock.dart';

/// How the app is drawn: following the system, or always light or dark.
enum AppearanceMode { system, light, dark }

/// How temperatures are shown, e.g. service temperatures.
enum TemperatureUnit { celsius, fahrenheit }

/// The learner's settings (backlog R1), as they are now.
class SettingsSnapshot {
  const SettingsSnapshot({
    this.appearance = AppearanceMode.system,
    this.temperatureUnit = TemperatureUnit.celsius,
    this.ageConfirmedAt,
    this.onboardedAt,
  });

  final AppearanceMode appearance;
  final TemperatureUnit temperatureUnit;

  /// When the learner confirmed being of legal drinking age (L-24).
  final DateTime? ageConfirmedAt;

  /// When the learner finished onboarding; null shows it again.
  final DateTime? onboardedAt;

  bool get isOnboarded => ageConfirmedAt != null && onboardedAt != null;
}

/// The learner's settings, kept in `user_settings`, one value per key
/// (backlog R1).
class LearnerSettings {
  LearnerSettings(this.db, {Clock? clock}) : _clock = clock ?? const Clock();

  final AppDatabase db;
  final Clock _clock;

  static const _appearance = 'appearance';
  static const _temperatureUnit = 'temperature_unit';
  static const _ageConfirmedAt = 'age_confirmed_at';
  static const _onboardedAt = 'onboarded_at';

  /// The settings as they change.
  Stream<SettingsSnapshot> watch() =>
      db.select(db.userSettings).watch().map(_snapshot);

  Future<SettingsSnapshot> current() async =>
      _snapshot(await db.select(db.userSettings).get());

  static SettingsSnapshot _snapshot(List<UserSetting> rows) {
    final values = {for (final row in rows) row.name: row.value};
    T? named<T extends Enum>(List<T> all, String key) {
      final name = values[key];
      return all.where((value) => value.name == name).firstOrNull;
    }

    DateTime? instant(String key) {
      final text = values[key];
      return text == null ? null : DateTime.tryParse(text);
    }

    return SettingsSnapshot(
      appearance:
          named(AppearanceMode.values, _appearance) ?? AppearanceMode.system,
      temperatureUnit:
          named(TemperatureUnit.values, _temperatureUnit) ??
          TemperatureUnit.celsius,
      ageConfirmedAt: instant(_ageConfirmedAt),
      onboardedAt: instant(_onboardedAt),
    );
  }

  Future<void> _set(String key, String value) => db
      .into(db.userSettings)
      .insertOnConflictUpdate(
        UserSettingsCompanion.insert(
          name: key,
          value: value,
          updatedAt: utcNow(_clock),
        ),
      );

  Future<void> setAppearance(AppearanceMode mode) =>
      _set(_appearance, mode.name);

  Future<void> setTemperatureUnit(TemperatureUnit unit) =>
      _set(_temperatureUnit, unit.name);

  /// Records that the learner confirmed being of legal drinking age.
  Future<void> confirmAge() =>
      _set(_ageConfirmedAt, utcNow(_clock).toIso8601String());

  /// Records that the learner finished onboarding, so it is not shown again.
  Future<void> completeOnboarding() =>
      _set(_onboardedAt, utcNow(_clock).toIso8601String());
}

/// [celsius] in the learner's [unit], rounded to whole degrees, e.g. "16 °C".
String formatTemperature(double celsius, TemperatureUnit unit) =>
    switch (unit) {
      TemperatureUnit.celsius => '${celsius.round()} °C',
      TemperatureUnit.fahrenheit => '${(celsius * 9 / 5 + 32).round()} °F',
    };
