import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/coverage/track_scope.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/authored_choice/authored_choice_format.dart';
import 'package:sommelier/core/questions/formats/case_criteria/case_criteria_format.dart';
import 'package:sommelier/core/questions/formats/short_answer/short_answer_format.dart';
import 'package:sommelier/core/questions/formats/typed/typed_format.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/historical_map_assets.dart';
import '../../../tool/curriculum/diploma_market_candidate.dart';

const lowerTracks = [
  'WSET_L1',
  'WSET_L2',
  'WSET_L3',
  'CMS_INTRODUCTORY',
  'CMS_CERTIFIED',
];
const caseKeys = ['us_entry', 'ew_retail', 'sweden_access'];
const flashcards = {
  'CASE_REASON': 'qt_case_reason_flashcard',
  'CASE_TRADEOFF': 'qt_case_tradeoff_flashcard',
  'CASE_LIMITATION': 'qt_case_limitation_flashcard',
};

void main() {
  final canonical = bundledDataset();
  final base = marketStructuralBaseline();
  final predecessor = marketPredecessor();
  final candidate = marketCandidate();
  final cohort = candidate.knowledgeItems
      .where((row) => row.id.startsWith('ki_d2market_'))
      .toList();
  final ids = cohort.map((row) => row.id).toSet();
  final principleIds = cohort
      .where((row) => row.relationType == 'PRINCIPLE_EXPLANATION')
      .map((row) => row.id)
      .toSet();
  test('registered release preview retains final metadata instead of resetting its version', () {
    final manifest = jsonDecode(
      jsonEncode(
        loadYaml(File('assets/curriculum/curriculum.yaml').readAsStringSync()),
      ),
    ) as Map<String, dynamic>;
    manifest
      ..['dataset_version'] = '0.24.72'
      ..['published_at'] = '2026-10-02T22:15:37.000Z'
      ..['includes'] = {
        ...marketIncludes,
        ...(manifest['includes'] as List).cast<String>(),
      }.toList();
    final text = jsonEncode(manifest);
    final finalRelease = marketCandidate(manifestText: text);
    expect(finalRelease.version, '0.24.72');
    expect(finalRelease.publishedAt, DateTime.utc(2026, 10, 2, 22, 15, 37));
    expect(
      finalRelease.knowledgeItems.where(
        (row) => row.id.startsWith('ki_d2market_'),
      ),
      hasLength(23),
    );
    expect(finalRelease.files.toSet(), hasLength(finalRelease.files.length));
    expect(validateDataset(finalRelease).errors, isEmpty);
    expect(bundledDataset().checksum, canonical.checksum);
  });

  test('candidate validates and preserves canonical release, rows and source URLs', () {
    expect(validateDataset(candidate).errors, isEmpty);
    expect(predecessor.version, '0.24.69');
    expect(
      predecessor.checksum,
      'sha256:72e48d8422f72e6ead8fe8dba4d6ebbcbd6f578b48749097e27e8e618f2479a3',
    );
    expect(bundledDataset().checksum, canonical.checksum);
    expect(
      candidate.version,
      canonical.knowledgeItems.any((row) => row.id.startsWith('ki_d2market_'))
          ? canonical.version
          : '0.24.71',
    );
    expect(candidate.publishedAt.isAfter(predecessor.publishedAt), isTrue);
    for (final section in base.locations.entries) {
      expect(
        candidate.locations[section.key]!.keys,
        containsAll(section.value.keys),
      );
    }
    final items = {for (final row in candidate.knowledgeItems) row.id: row};
    for (final row in base.knowledgeItems) {
      expect(items[row.id]!.toJson(), row.toJson(), reason: row.id);
    }
    final sources = {for (final row in candidate.sourceCitations) row.id: row};
    for (final row in base.sourceCitations) {
      expect(sources[row.id]!.toJson(), row.toJson(), reason: row.id);
    }
    expect(cohort, hasLength(23));
    expect(principleIds, hasLength(11));
    expect(
      candidate.knowledgeNodes.where((row) => row.id.startsWith('n_d2market_')),
      hasLength(37),
    );
    for (final row in cohort) {
      expect(row.verificationStatus, 'unverified');
      expect(row.mcqDisabled, isTrue);
      expect(row.domainId, 'business');
      final mapping = candidate.certificationKnowledgeMappings
          .where((m) => m.knowledgeItemId == row.id)
          .toList();
      expect(mapping, hasLength(1));
      expect(mapping.single.certificationId, 'WSET_L4');
      expect(mapping.single.importance, 'core');
      expect(
        mapping.single.minimumDepth,
        principleIds.contains(row.id) ? 2 : 3,
      );
    }
  });

  test(
    'legal distinctions cite public primary texts without duplicate URLs',
    () {
      const legal = {
        'ki_d2market_us_federal': {'src_d2market_us_203'},
        'ki_d2market_ew_authority': {'src_d2market_ew_17'},
        'ki_d2market_ew_scope': {'src_d2market_ew_17'},
        'ki_d2market_ew_personal': {
          'src_d2market_ew_19',
          'src_d2market_ew_111',
        },
        'ki_d2market_se_retail': {'src_d2market_sweden_act'},
        'ki_d2market_se_serving': {'src_d2market_sweden_act'},
        'ki_d2market_se_farm': {'src_d2market_sweden_act'},
      };
      final sources = {
        for (final row in candidate.sourceCitations) row.id: row,
      };
      for (final item in cohort) {
        final citations = candidate.knowledgeItemCitations
            .where((row) => row.knowledgeItemId == item.id)
            .toList();
        expect(citations, isNotEmpty, reason: item.id);
        for (final row in citations) {
          expect(row.locator, isNotEmpty);
          expect(sources[row.sourceCitationId]!.url, startsWith('https://'));
        }
        if (legal[item.id] case final expected?) {
          expect(
            citations.map((row) => row.sourceCitationId),
            containsAll(expected),
          );
          for (final id in expected) {
            expect(sources[id]!.kind, 'legislation');
          }
        }
      }
      String normalize(String value) => value.replaceFirst(RegExp(r'/$'), '');
      final originalIds = base.sourceCitations.map((row) => row.id).toSet();
      final originalUrls = base.sourceCitations
          .map((row) => row.url)
          .whereType<String>()
          .map(normalize)
          .toSet();
      final added = candidate.sourceCitations
          .where((row) => !originalIds.contains(row.id))
          .toList();
      expect(added, hasLength(14));
      final urls = added.map((row) => normalize(row.url!)).toSet();
      expect(urls, hasLength(14));
      expect(urls.intersection(originalUrls), isEmpty);
    },
  );

  test('every case role has explicit market and commercial prerequisites', () {
    const expected = {
      'us_entry': {
        'ki_d2market_us_tiers',
        'ki_d2market_us_variation',
        'ki_d2market_us_federal',
        'ki_biz_payment_timing',
        'ki_biz_profit_cash',
        'ki_biz_routes_partner_fit',
      },
      'ew_retail': {
        'ki_d2market_ew_authority',
        'ki_d2market_ew_scope',
        'ki_d2market_ew_personal',
        'ki_biz_routes_retail_access',
        'ki_biz_profit_cash',
      },
      'sweden_access': {
        'ki_d2market_se_retail',
        'ki_d2market_se_mission',
        'ki_d2market_se_supplier',
        'ki_d2market_se_serving',
        'ki_d2market_se_farm',
        'ki_biz_routes_partner_fit',
        'ki_biz_routes_ontrade_fit',
      },
    };
    for (final key in caseKeys) {
      for (final role in ['action', 'reason', 'tradeoff', 'limitation']) {
        final actual = candidate.knowledgeItemPrerequisites
            .where(
              (row) => row.knowledgeItemId == 'ki_d2market_case_${key}_$role',
            )
            .map((row) => row.prerequisiteItemId)
            .toSet();
        expect(actual, expected[key], reason: '$key $role');
      }
    }
  });

  test('preview scope adds 14 subjects only to Diploma routes', () {
    final original = TrackScopeManifest.parse(
      File(marketScopePath).readAsStringSync(),
    );
    final preview = TrackScopeManifest.parse(marketCandidateScope());
    final subjects = cohort.map((row) => row.subjectId).toSet();
    expect(subjects, hasLength(14));
    for (final track in original.tracks.entries) {
      final updated = {
        for (final objective in preview.tracks[track.key]!.objectives)
          objective.id: objective,
      };
      for (final objective in track.value.objectives) {
        final old = objective.covers?.within ?? <String>{};
        final added = updated[objective.id]!.covers?.within ?? <String>{};
        expect(old.difference(added), isEmpty);
        expect(
          added.difference(old),
          objective.id == 'wset_l4.business.routes'
              ? subjects.difference(old)
              : isEmpty,
          reason: objective.id,
        );
      }
    }
  });

  test('real choices and typed questions grade alternatives and isolate lower tracks', () async {
    final db = openTestDatabase();
    try {
      final fixed = Clock.fixed(candidate.publishedAt);
      await CurriculumIngester(
        db,
        clock: fixed,
        assets: (path) async => File(path).readAsBytesSync(),
      ).ingest(candidate);
      final planner = StudyPlanner(db, clock: fixed);
      for (final track in lowerTracks) {
        expect(
          (await planner.cards(track))
              .map((row) => row.itemId)
              .toSet()
              .intersection(ids),
          isEmpty,
          reason: track,
        );
      }
      final cards = {
        for (final row in await planner.cards('WSET_L4')) row.itemId: row,
      };
      expect(cards.keys, containsAll(ids));
      final presenter = ExercisePresenter(db, clock: fixed);
      final choices = AuthoredChoiceFormat.itemChoicesOf(
        candidate.questionTemplates.singleWhere(
          (row) => row.id == 'qt_d2market_choice_11',
        ),
      );
      expect(choices.keys.toSet(), principleIds);
      final reviews = ReviewService(db, clock: fixed);
      for (final id in principleIds) {
        expect(
          cards[id]!.formats.map((row) => row.questionTemplateId),
          contains('qt_d2market_choice_11'),
        );
        final question = await presenter.present(
          id,
          'qt_d2market_choice_11',
          certificationId: 'WSET_L4',
          seed: 17,
        ) as AuthoredChoiceQuestion;
        final cue = choices[id]!;
        expect(question.options, hasLength(4));
        expect(
          question.options.map((row) => row.name).toSet(),
          cue.options.toSet(),
        );
        expect(question.answer.name, cue.options[cue.correctIndex]);
        expect(question.prompt, isNot(contains(question.answer.name)));
        expect(question.explanation, cue.explanation);
        for (final option in question.options) {
          expect(
            const AuthoredChoiceFormat().grade(question, option).single.rating,
            option == question.answer ? fsrs.Rating.good : fsrs.Rating.again,
          );
        }
        await reviews.recordExercise(
          question,
          const AuthoredChoiceFormat().grade(question, question.answer),
        );
      }
      const typed = {
        'ki_d2market_us_tiers': ('retailer', 'manufacturer'),
        'ki_d2market_ew_personal': ('personal licence', 'premises licence'),
        'ki_d2market_se_retail': ('Systembolaget', 'TABC'),
      };
      for (final entry in typed.entries) {
        final question = await presenter.present(
          entry.key,
          'qt_d2market_typed_3',
          certificationId: 'WSET_L4',
          seed: 17,
        ) as TypedQuestion;
        expect(question.options, isEmpty);
        expect(
          const TypedFormat().grade(question, entry.value.$1).single.rating,
          fsrs.Rating.good,
        );
        expect(
          const TypedFormat().grade(question, entry.value.$2).single.rating,
          fsrs.Rating.again,
        );
      }
      expect(await db.select(db.reviewEvents).get(), hasLength(11));
      expect(
        (await db.select(db.reviewStates).get())
            .map((row) => row.knowledgeItemId)
            .toSet(),
        principleIds,
      );
    } finally {
      await db.close();
    }
  });

  test('three cases gate on co-roles, grade independently and preserve self-review boundaries', () async {
    final db = openTestDatabase();
    try {
      final fixed = Clock.fixed(candidate.publishedAt);
      final generation = await CurriculumIngester(
        db,
        clock: fixed,
        assets: (path) async => File(path).readAsBytesSync(),
      ).ingest(candidate);
      final presenter = ExercisePresenter(db, clock: fixed);
      final flashcard = QuestionPresenter(db);
      final reviews = ReviewService(db, clock: fixed);
      final planner = StudyPlanner(db, clock: fixed);
      for (final key in caseKeys) {
        final action = 'ki_d2market_case_${key}_action';
        final node = 'n_d2market_case_$key';
        final caseIds = cohort
            .where((row) => row.subjectId == node)
            .map((row) => row.id)
            .toSet();
        await expectLater(
          presenter.present(
            action,
            'qt_d2market_criteria_3',
            certificationId: 'WSET_L4',
            seed: 9,
          ),
          throwsArgumentError,
        );
        for (final track in lowerTracks) {
          await expectLater(
            presenter.present(
              action,
              'qt_d2market_written_3',
              certificationId: track,
              seed: 9,
            ),
            throwsArgumentError,
          );
        }
        for (final role in ['CASE_REASON', 'CASE_TRADEOFF']) {
          final item = cohort.singleWhere(
            (row) => row.subjectId == node && row.relationType == role,
          );
          await reviews.gradeFlashcard(
            await flashcard.present(item.id, flashcards[role]!, seed: 9),
            fsrs.Rating.good,
          );
        }
        final partial = (await planner.cards('WSET_L4'))
            .singleWhere((row) => row.itemId == action);
        expect(
          partial.formats.map((row) => row.mode),
          isNot(contains('case_criteria')),
        );
        final limitation = cohort.singleWhere(
          (row) =>
              row.subjectId == node && row.relationType == 'CASE_LIMITATION',
        );
        await reviews.gradeFlashcard(
          await flashcard.present(
            limitation.id,
            flashcards['CASE_LIMITATION']!,
            seed: 9,
          ),
          fsrs.Rating.good,
        );
        final exercise = await presenter.present(
          action,
          'qt_d2market_criteria_3',
          certificationId: 'WSET_L4',
          seed: 9,
        ) as CaseCriteriaExercise;
        expect(exercise.itemIds.toSet(), caseIds);
        expect(exercise.options, hasLength(6));
        expect(
          exercise.options.map((row) => row.summary).toSet(),
          hasLength(6),
        );
        expect(
          exercise.criteria.every(
            (row) => row.sources.isNotEmpty && row.assertion.isNotEmpty,
          ),
          isTrue,
        );
        final correct = {
          for (final row in exercise.criteria) row.role: row.itemId,
        };
        const format = CaseCriteriaFormat();
        final grades = format.grade(exercise, CaseCriteriaResponse(correct));
        expect(grades.every((row) => row.rating == fsrs.Rating.good), isTrue);
        for (final wrong in exercise.options.where(
          (row) => row.explanation != null,
        )) {
          for (final role in caseCriterionRoles) {
            final mixed = format.grade(
              exercise,
              CaseCriteriaResponse({...correct, role: wrong.id}),
            );
            for (final grade in mixed) {
              expect(
                grade.rating,
                grade.itemId == correct[role]
                    ? fsrs.Rating.again
                    : fsrs.Rating.good,
              );
            }
          }
        }
        expect(
          () => format.grade(
            exercise,
            CaseCriteriaResponse({...correct, 'CASE_ACTION': 'foreign_option'}),
          ),
          throwsArgumentError,
        );
        await reviews.recordExercise(exercise, grades);
        final written = await presenter.present(
          action,
          'qt_d2market_written_3',
          certificationId: 'WSET_L4',
          seed: 9,
        ) as ShortAnswerExercise;
        expect(written.prompt, exercise.prompt);
        expect(written.itemIds.toSet(), caseIds);
        expect(written.keyPoints, hasLength(4));
        final omitted = const ShortAnswerFormat().grade(
          written,
          ShortAnswerResponse(
            'My own conditional analysis',
            {...caseIds}..remove(limitation.id),
          ),
        );
        expect(
          omitted.singleWhere((row) => row.itemId == limitation.id).rating,
          fsrs.Rating.again,
        );
        expect(
          omitted
              .where((row) => row.itemId != limitation.id)
              .every((row) => row.rating == fsrs.Rating.good),
          isTrue,
        );
      }
      expect(
        (await db.select(db.reviewEvents).get()).where(
          (row) => row.questionTemplateId == 'qt_d2market_criteria_3',
        ),
        hasLength(12),
      );
      const path = 'assets/curriculum/coverage_policy.yaml';
      final report = await CoverageChecker(
        db,
        CoveragePolicy.parse(File(path).readAsStringSync(), path: path),
      ).check('WSET_L4', on: '2026-10-02', skipped: generation.skipped);
      final measured = report.items
          .where((row) => ids.contains(row.id))
          .toList();
      expect(measured, hasLength(23));
      expect(measured.every((row) => row.hasUsefulPractice), isTrue);
      final routes = TrackScopeManifest.parse(marketCandidateScope())
          .tracks['WSET_L4']!
          .objectives
          .singleWhere((row) => row.id == 'wset_l4.business.routes');
      expect(measured.every(routes.covers!.matches), isTrue);
    } finally {
      await db.close();
    }
  });

  test('real canonical-to-candidate upgrade preserves learner reviews, settings and existing items', () async {
    final db = openTestDatabase();
    try {
      final ingester = CurriculumIngester(
        db,
        clock: Clock.fixed(candidate.publishedAt),
        assets: (path) async => File(path).readAsBytesSync(),
      );
      await CurriculumIngester(
        db,
        clock: Clock.fixed(candidate.publishedAt),
        assets: (path) => historicalMapAsset(predecessor, path),
      ).ingest(predecessor);
      const id = 'ki_biz_routes_partner_fit';
      final template = (await db.select(db.questions).get()).firstWhere(
        (row) =>
            row.knowledgeItemId == id &&
            predecessor.questionTemplates
                    .singleWhere((t) => t.id == row.questionTemplateId)
                    .mode ==
                'flashcard',
      );
      final question = await QuestionPresenter(db)
          .present(id, template.questionTemplateId, seed: 42);
      await ReviewService(
        db,
        clock: Clock.fixed(predecessor.publishedAt),
      ).gradeFlashcard(question, fsrs.Rating.good);
      await db.customStatement(
        "INSERT INTO user_settings(name,value,updated_at) VALUES ('d2_market_upgrade_probe','preserve','2026-10-02T02:00:00.000Z')",
      );
      final events = (await db.select(db.reviewEvents).get())
          .map((row) => row.toJson())
          .toList();
      final states = (await db.select(db.reviewStates).get())
          .map((row) => row.toJson())
          .toList();
      final settings = (await db.select(db.userSettings).get())
          .map((row) => row.toJson())
          .toList();
      expect(
        await ingester.ensureCurrent(candidate),
        IngestionOutcome.upgraded,
      );
      expect(
        (await db.select(db.reviewEvents).get())
            .map((row) => row.toJson())
            .toList(),
        events,
      );
      expect(
        (await db.select(db.reviewStates).get())
            .map((row) => row.toJson())
            .toList(),
        states,
      );
      expect(
        (await db.select(db.userSettings).get())
            .map((row) => row.toJson())
            .toList(),
        settings,
      );
      final installed = {
        for (final row in await db.select(db.knowledgeItems).get()) row.id: row,
      };
      for (final row in predecessor.knowledgeItems) {
        expect(installed, contains(row.id), reason: row.id);
      }
      for (final row in candidate.knowledgeItems) {
        expect(installed[row.id]!.toJson(), row.toJson(), reason: row.id);
      }
      expect(installed.keys, containsAll(ids));
      expect(
        await ingester.ensureCurrent(candidate),
        IngestionOutcome.upToDate,
      );
    } finally {
      await db.close();
    }
  });
}
