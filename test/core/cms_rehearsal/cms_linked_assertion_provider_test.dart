import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/cms_rehearsal/cms_rehearsal_providers.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/database/database_providers.dart';

import '../../support/fixture.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = openTestDatabase();
    await seedCurriculum(db);
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<String?> linkedAssertion(String id) async {
    final provider = cmsLinkedAssertionProvider(id);
    final subscription = container.listen(provider, (_, _) {});
    try {
      return await container.read(provider.future);
    } finally {
      subscription.close();
    }
  }

  test('linked facts retain exact ID lookup and historical assertion text', () async {
    expect(
      await linkedAssertion('ki_chablis_grape'),
      'Chardonnay is the only principal grape variety permitted in the Chablis AOC.',
    );

    // Saved links may outlive current track membership or relation eligibility.
    // This read is intentionally distinct from selecting new CMS questions.
    const historical = '  Évidence retained.\nA conditional limitation.  ';
    await db.writeCurriculum(() async {
      await db.customStatement(
        'UPDATE knowledge_items SET assertion_text = ? WHERE id = ?',
        [historical, 'ki_barolo_min_ageing'],
      );
      await db.customStatement(
        "UPDATE knowledge_relations SET valid_until = '2000-01-01' "
        "WHERE subject_id = 'n_geo_barolo' AND relation_type = 'MIN_AGEING'",
      );
    });
    expect(await linkedAssertion('ki_barolo_min_ageing'), historical);
    expect(await db.select(db.userSettings).get(), isEmpty);
    expect(await db.select(db.reviewEvents).get(), isEmpty);
    expect(await db.select(db.reviewStates).get(), isEmpty);
  });

  test(
    'missing linked IDs return null without substituting another fact',
    () async {
      expect(await linkedAssertion('ki_missing_cms_link'), isNull);
      expect(await linkedAssertion("missing' OR 1=1 --"), isNull);
      expect(await db.select(db.userSettings).get(), isEmpty);
      expect(await db.select(db.reviewEvents).get(), isEmpty);
      expect(await db.select(db.reviewStates).get(), isEmpty);
    },
  );
}
