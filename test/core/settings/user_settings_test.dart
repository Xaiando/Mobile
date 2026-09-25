import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/settings/user_settings.dart';
import 'package:sommelier/core/study/learner_profile.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;

  setUp(() {
    db = openTestDatabase();
    time = TestClock(DateTime.utc(2026, 10, 1, 9));
  });
  tearDown(() => db.close());

  test('settings start at their defaults and keep what is set', () async {
    final settings = LearnerSettings(db, clock: time.clock);
    final initial = await settings.current();
    expect(initial.appearance, AppearanceMode.system);
    expect(initial.temperatureUnit, TemperatureUnit.celsius);
    expect(initial.isOnboarded, isFalse);

    await settings.setAppearance(AppearanceMode.dark);
    await settings.setTemperatureUnit(TemperatureUnit.fahrenheit);
    await settings.confirmAge();
    expect((await settings.current()).isOnboarded, isFalse);
    time.advance(const Duration(minutes: 2));
    await settings.completeOnboarding();

    final now = await settings.current();
    expect(now.appearance, AppearanceMode.dark);
    expect(now.temperatureUnit, TemperatureUnit.fahrenheit);
    expect(now.ageConfirmedAt, DateTime.utc(2026, 10, 1, 9));
    expect(now.onboardedAt, DateTime.utc(2026, 10, 1, 9, 2));
    expect(now.isOnboarded, isTrue);
  });

  test('temperatures show in the learner\'s unit', () {
    expect(formatTemperature(16, TemperatureUnit.celsius), '16 °C');
    expect(formatTemperature(16, TemperatureUnit.fahrenheit), '61 °F');
    expect(formatTemperature(7.5, TemperatureUnit.fahrenheit), '46 °F');
  });

  test('session limits need a track, and new items never exceed the '
      'session', () async {
    await CurriculumIngester(db).ensureCurrent(bundledDataset());
    final profiles = LearnerProfiles(db, clock: time.clock);
    await expectLater(
      profiles.setSessionLimits(sessionSize: 20, newItems: 5),
      throwsStateError,
    );
    await profiles.selectTrack('WSET_L3');
    final profile = await profiles.setSessionLimits(
      sessionSize: 10,
      newItems: 12,
    );
    expect((profile.sessionSize, profile.newItemsPerSession), (10, 10));
  });
}
