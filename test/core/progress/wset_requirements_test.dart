import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/progress/wset_progress.dart';
import 'package:sommelier/core/progress/wset_requirements.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/study/review_service.dart';

import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;

  WsetScope scope({
    String item = 'ki_chablis_grape',
    String kind = 'grapes',
    List<String> formats = const ['mcq'],
    bool reviewed = true,
    bool complete = true,
  }) => WsetScope([
    for (var level = 1; level <= 4; level++)
      WsetLevelScope(
        certificationId: 'WSET_L$level',
        title: 'Level $level',
        curriculumComplete: level == 3 && complete,
        gaps: level == 3 && complete ? [] : ['Further authoring required.'],
        sourceUrl: 'https://www.wsetglobal.com/',
        requirements: level != 3
            ? []
            : [
                WsetRequirement(
                  id: 'chablis_profile',
                  title: 'Original Chablis requirement',
                  reviewed: reviewed,
                  dimensions: [
                    WsetEvidenceDimension(
                      kind: kind,
                      itemIds: [item],
                      formats: formats,
                    ),
                  ],
                ),
              ],
      ),
  ]);

  Future<WsetLevelProgress> snapshot(WsetScope scope) async =>
      (await WsetProgressRepository(
        db,
        scope: scope,
        clock: time.clock,
      ).snapshot()).levels[2];

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await seedSchedulerConfig(db);
  });
  tearDown(() => db.close());

  test(
    'required facts are a separate denominator from optional atlas details',
    () async {
      final result = await snapshot(scope());
      expect(result.counts.mapped, 2);
      expect(result.requiredCounts!.mapped, 1);
      expect(result.optionalCounts!.mapped, 1);
      expect(result.requirements.single.counts.available, 1);
      expect(result.nextItems.single.itemId, 'ki_chablis_grape');
      expect(result.appLevelComplete, isFalse);
    },
  );

  test(
    'optional unreviewed material does not block a mastered required topic',
    () async {
      final reviews = ReviewService(
        db,
        clock: time.clock,
        schedulerFactory: unfuzzedScheduler,
      );
      for (final days in [0, 3, 4]) {
        time.advance(Duration(days: days));
        await reviews.record(
          knowledgeItemId: 'ki_chablis_grape',
          questionTemplateId: 'qt_ppg_fwd_mcq',
          rating: fsrs.Rating.easy,
        );
      }
      final result = await snapshot(scope());
      expect(result.requiredCounts!.mastered, 1);
      expect(result.optionalCounts!.studied, 0);
      expect(result.appLevelComplete, isTrue);
      expect(result.requirements.single.complete, isTrue);
      expect(result.corePracticeCoverage!.core, 2);
      expect(result.corePracticeCoverage!.useful, 0);
      expect(result.corePracticeCoverage!.complete, isFalse);
    },
  );

  test(
    'expiry retains the required denominator and historical reviews',
    () async {
      await db.writeCurriculum(
        () => runSql(db, [
          "UPDATE knowledge_relations SET valid_until='2026-01-01' WHERE relation_type='PERMITS_PRINCIPAL_GRAPE' AND subject_id='n_geo_chablis'",
        ]),
      );
      final result = await snapshot(scope());
      expect(result.requiredCounts!.mapped, 1);
      expect(result.requiredCounts!.available, 0);
      expect(result.requiredCounts!.unavailable, 1);
      expect(result.appLevelComplete, isFalse);
    },
  );

  test(
    'unknown IDs fail visibly and known unmapped facts remain unavailable',
    () async {
      await expectLater(
        snapshot(scope(item: 'ki_missing')),
        throwsFormatException,
      );
      final result = await snapshot(
        scope(item: 'ki_barolo_min_ageing', kind: 'labels'),
      );
      expect(result.requiredCounts!.mapped, 1);
      expect(result.requiredCounts!.unavailable, 1);
      expect(result.appLevelComplete, isFalse);
    },
  );

  test(
    'practice must serve a required mode rather than any card format',
    () async {
      final result = await snapshot(scope(formats: ['short_answer']));
      expect(result.counts.available, 2);
      expect(result.requiredCounts!.available, 0);
      expect(result.appLevelComplete, isFalse);
    },
  );

  test(
    'location-only facts cannot satisfy production or style explanations',
    () async {
      await db.writeCurriculum(
        () => runSql(db, [
          "INSERT INTO knowledge_items (id,subject_id,relation_type,object_id,domain_id,assertion_text,last_verified_at) VALUES ('ki_chablis_location','n_geo_chablis','LOCATED_IN','n_geo_burgundy','geography','Chablis location.','2026-01-01T00:00:00.000Z')",
        ]),
      );
      await expectLater(
        snapshot(scope(item: 'ki_chablis_location', kind: 'production')),
        throwsFormatException,
      );
      await expectLater(
        snapshot(scope(item: 'ki_chablis_grape', kind: 'location')),
        throwsFormatException,
      );
    },
  );

  test('coverage cannot claim complete with unreviewed requirements', () async {
    expect(() => scope(reviewed: false).validate(), throwsFormatException);
    final result = await snapshot(scope(reviewed: false, complete: false));
    expect(result.requirements.single.complete, isFalse);
    expect(result.appLevelComplete, isFalse);
  });

  test('map practice cannot stand in for explanatory teaching', () {
    for (final kind in WsetEvidenceDimension.kinds) {
      final evidence = WsetEvidenceDimension(
        kind: kind,
        itemIds: const ['ki_example'],
        formats: const ['map_grape'],
      );
      if (kind == 'location' || kind == 'grapes') {
        expect(evidence.validate, returnsNormally);
      } else {
        expect(evidence.validate, throwsFormatException, reason: kind);
      }
    }
  });

  test('parser rejects empty and duplicate evidence instead of disappearing topics', () {
    final row = {
      'id': 'region_profile',
      'title': 'Region',
      'reviewed': false,
      'dimensions': [
        {
          'kind': 'style',
          'itemIds': ['ki_one'],
          'formats': ['flashcard'],
        },
      ],
    };
    WsetRequirement.fromJson(row).validate();
    for (final invalid in [
      {...row, 'dimensions': <Object?>[]},
      {
        ...row,
        'dimensions': [
          ...row['dimensions'] as List,
          ...row['dimensions'] as List,
        ],
      },
      {
        ...row,
        'dimensions': [
          {
            'kind': 'style',
            'itemIds': <String>[],
            'formats': ['flashcard'],
          },
        ],
      },
      {
        ...row,
        'dimensions': [
          {
            'kind': 'style',
            'itemIds': ['ki_one'],
            'formats': ['unregistered'],
          },
        ],
      },
    ]) {
      expect(
        () => WsetRequirement.fromJson(
          jsonDecode(jsonEncode(invalid)) as Map<String, dynamic>,
        ).validate(),
        throwsA(isA<Exception>()),
      );
    }
  });
}
