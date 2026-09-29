import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/geography/map_practice_catalog.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(DateTime.utc(2026, 10, 1, 9));
    await CurriculumIngester(
      db,
      clock: time.clock,
    ).ensureCurrent(bundledDataset());
  });
  tearDown(() => db.close());

  test('country and subregion choices contain only served map facts', () async {
    final planner = StudyPlanner(db, clock: time.clock);
    final cards = await planner.cards('WSET_L3');
    final scopes = await MapPracticeCatalog(db)
        .scopes(cards, on: '2026-10-01', now: time.now);
    final france = scopes.singleWhere((s) => s.id == 'n_geo_france');
    final burgundy = scopes.singleWhere((s) => s.id == 'n_geo_burgundy');
    final chablis = scopes.singleWhere((s) => s.id == 'n_geo_chablis');

    expect(chablis.countryName, 'France');
    expect(chablis.path, contains('Burgundy'));
    expect(france.itemIds, containsAll(burgundy.itemIds));
    expect(burgundy.itemIds, containsAll(chablis.itemIds));
    expect(chablis.itemIds, contains('ki_chablis_location'));
    expect(chablis.readyCount, chablis.factCount);
    final served = {for (final card in cards) card.itemId: card};
    for (final scope in scopes) {
      for (final id in scope.itemIds) {
        expect(
          served[id]!.formats.any((format) => format.mode.startsWith('map_')),
          isTrue,
          reason: '${scope.name} offered $id without a map format',
        );
      }
    }
  });

  test('map-only plan keeps the track mapping and ordinary budgets', () async {
    final planner = StudyPlanner(db, clock: time.clock);
    const modes = {'map_locate', 'map_identify', 'map_pair', 'map_grape'};
    final mapPlan = await planner.plan(
      certificationId: 'WSET_L3',
      itemIds: {'ki_chablis_location', 'ki_chablis_grape'},
      formatModes: modes,
      sessionSize: 2,
      newItems: 1,
    );
    expect(mapPlan, isNotNull);
    expect(mapPlan!.cards, hasLength(1));
    expect(mapPlan.newAvailable, greaterThanOrEqualTo(1));
    expect(
      mapPlan.cards.single.formats.map((f) => f.mode),
      everyElement(isIn(modes)),
    );
    expect(
      mapPlan.cards.single.itemId,
      isIn({'ki_chablis_location', 'ki_chablis_grape'}),
    );
  });
}
