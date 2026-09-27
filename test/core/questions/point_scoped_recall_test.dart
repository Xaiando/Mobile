import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/short_answer/short_answer_format.dart';
import 'package:sommelier/core/questions/formats/typed/typed_format.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/study/review_service.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

const primary = 'ki_shared_primary';
const lowerPeer = 'ki_shared_lower_peer';
const advanced = 'ki_shared_advanced';
const expired = 'ki_shared_expired';
const shortTemplate = 'qt_shared_short';
const cueTemplate = 'qt_shared_cue';
const broadTemplate = 'qt_shared_typed';
const primaryPoint = 'Cooling changes sugar accumulation';
const cuePrompt =
    'In this cooling example, does sugar accumulation become slower or faster?';

Map<String, dynamic> pointFixture({int lowerDepth = 1}) {
  final data = copyOf(minimalDataset());
  rowsOf(data, 'certifications').add({
    'id': 'WSET_L3',
    'organization': 'WSET',
    'level': 3,
    'display_name': 'WSET Level 3',
    'includes_certification_id': 'WSET_L2',
    'is_selectable': true,
  });
  rowsOf(
    data,
    'node_types',
  ).add({'id': 'learning_point', 'label': 'learning point'});
  rowsOf(data, 'relation_types').add({
    'id': 'PRINCIPLE_EXPLANATION',
    'label': 'explains',
    'reverse_label': 'is explained by',
    'cardinality': 'many',
    'default_domain_id': 'geography',
  });
  rowsOf(data, 'relation_type_signatures').add({
    'relation_type': 'PRINCIPLE_EXPLANATION',
    'subject_node_type': 'appellation',
    'object_node_type': 'learning_point',
  });
  for (final (id, name, level, depth) in [
    (primary, primaryPoint, 'WSET_L2', 2),
    (lowerPeer, 'Wind helps canopy drying', 'WSET_L2', lowerDepth),
    (advanced, 'Sorting reduces crop volume', 'WSET_L3', 2),
    (expired, 'Retired technique affects flavour', 'WSET_L2', 2),
  ]) {
    final node = 'n_$id';
    rowsOf(
      data,
      'knowledge_nodes',
    ).add({'id': node, 'node_type': 'learning_point', 'name': name});
    rowsOf(data, 'knowledge_relations').add({
      'subject_id': 'n_geo_chablis',
      'relation_type': 'PRINCIPLE_EXPLANATION',
      'object_id': node,
      'valid_from': '1900-01-01',
      if (id == expired) 'valid_until': '2026-01-01',
    });
    rowsOf(data, 'knowledge_items').add({
      'id': id,
      'subject_id': 'n_geo_chablis',
      'relation_type': 'PRINCIPLE_EXPLANATION',
      'object_id': node,
      'domain_id': 'geography',
      'assertion_text': '$name in this supplied example.',
      'mcq_disabled': true,
      'last_verified_at': '2026-01-01T00:00:00.000Z',
    });
    rowsOf(
      data,
      'knowledge_item_citations',
    ).add({'knowledge_item_id': id, 'source_citation_id': 'src_test_law'});
    rowsOf(data, 'certification_knowledge_mappings').add({
      'certification_id': level,
      'knowledge_item_id': id,
      'importance': 'core',
      'minimum_depth': depth,
    });
  }
  rowsOf(data, 'node_alternative_names')
    ..add({
      'knowledge_node_id': 'n_$primary',
      'name': 'Cooling modifies ripening',
      'kind': 'synonym',
    })
    ..add({
      'knowledge_node_id': 'n_$advanced',
      'name': 'Sorting lower crop quantity',
      'kind': 'synonym',
    });
  rowsOf(data, 'question_templates').addAll([
    {
      'id': 'qt_shared_flashcard',
      'relation_type': 'PRINCIPLE_EXPLANATION',
      'direction': 'forward',
      'mode': 'flashcard',
      'prompt_template': '{subject.name}',
    },
    {
      'id': broadTemplate,
      'relation_type': 'PRINCIPLE_EXPLANATION',
      'direction': 'forward',
      'mode': 'typed',
      'prompt_template': '{subject.name} Recall a learning point.',
    },
    {
      'id': shortTemplate,
      'relation_type': 'PRINCIPLE_EXPLANATION',
      'direction': 'forward',
      'mode': 'short_answer',
      'prompt_template': 'Explain the supplied points for {subject.name}.',
      'parameters': {
        'key_points': {'PRINCIPLE_EXPLANATION': 'Learning point'},
      },
    },
    {
      'id': cueTemplate,
      'relation_type': 'PRINCIPLE_EXPLANATION',
      'direction': 'forward',
      'mode': 'typed',
      'variant': 'point_scoped_cue',
      'prompt_template': '{subject.name}',
      'parameters': {
        'item_cues': {
          primary: {
            'prompt': cuePrompt,
            'acceptedAnswers': ['slower sugar accumulation', 'slower'],
          },
        },
      },
    },
  ]);
  return data;
}

void main() {
  late AppDatabase db;
  late TestClock time;
  late ExercisePresenter presenter;
  late ReviewService reviews;

  Future<void> install({int lowerDepth = 1}) async {
    await CurriculumIngester(
      db,
      clock: time.clock,
    ).ingest(datasetOf(pointFixture(lowerDepth: lowerDepth)));
  }

  setUp(() {
    db = openTestDatabase();
    time = TestClock(DateTime.utc(2026, 10, 1, 9));
    presenter = ExercisePresenter(db, clock: time.clock);
    reviews = ReviewService(db, clock: time.clock);
  });
  tearDown(() => db.close());

  test('short answer filters studied advanced and unserved siblings before selection', () async {
    await install();
    await reviews.record(
      knowledgeItemId: advanced,
      questionTemplateId: broadTemplate,
      rating: fsrs.Rating.good,
    );
    await reviews.record(
      knowledgeItemId: lowerPeer,
      questionTemplateId: 'qt_shared_flashcard',
      rating: fsrs.Rating.good,
    );
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
    final lower = await presenter.present(
      primary,
      shortTemplate,
      seed: 3,
      certificationId: 'WSET_L2',
    ) as ShortAnswerExercise;
    expect(lower.itemIds, [
      primary,
    ], reason: 'one valid point is better than leaking another');
    final eventsBefore = (await db.select(db.reviewEvents).get()).length;
    await reviews.recordExercise(
      lower,
      const ShortAnswerFormat().grade(
        lower,
        const ShortAnswerResponse('My supplied explanation.', {primary}),
      ),
    );
    final events = await db.select(db.reviewEvents).get();
    expect(events.length, eventsBefore + 1);
    expect(
      events
          .where((event) => event.questionTemplateId == shortTemplate)
          .single
          .knowledgeItemId,
      primary,
    );
    final higher = await presenter.present(
      primary,
      shortTemplate,
      seed: 3,
    ) as ShortAnswerExercise;
    expect(higher.itemIds, containsAll([primary, advanced]));
    expect(higher.itemIds, isNot(contains(lowerPeer)));
    expect(higher.itemIds, isNot(contains(expired)));
    await expectLater(
      presenter.present(
        advanced,
        shortTemplate,
        seed: 3,
        certificationId: 'WSET_L2',
      ),
      throwsArgumentError,
    );
  });

  test(
    'eligible lower siblings remain while unmapped and expired points do not',
    () async {
      await install(lowerDepth: 2);
      final exercise = await presenter.present(
        primary,
        shortTemplate,
        seed: 7,
        certificationId: 'WSET_L2',
      ) as ShortAnswerExercise;
      expect(exercise.itemIds, unorderedEquals([primary, lowerPeer]));
      expect(
        () => const ShortAnswerFormat().grade(
          exercise,
          const ShortAnswerResponse('unsupported claim', {advanced}),
        ),
        throwsArgumentError,
      );
    },
  );

  test('cue asks and grades the exact responsive answer, never another point or generic label', () async {
    await install();
    final question =
        await presenter.present(primary, cueTemplate, seed: 1) as TypedQuestion;
    expect(question.prompt, cuePrompt);
    expect(question.answer.nodeId, 'n_$primary');
    expect(question.answer.name, 'slower sugar accumulation');
    expect(question.canonicalAnswer, primaryPoint);
    final format = const TypedFormat();
    for (final answer in ['slower', 'slower sugar accumulation', 'SLOWER']) {
      expect(format.grade(question, answer).single.rating, fsrs.Rating.good);
      expect(format.grade(question, answer).single.itemId, primary);
    }
    for (final answer in [
      primaryPoint,
      'Cooling modifies ripening',
      'Sorting reduces crop volume',
      'Sorting lower crop quantity',
      'Wind helps canopy drying',
    ]) {
      expect(
        format.grade(question, answer).single.rating,
        fsrs.Rating.again,
        reason: '$answer does not answer the authored cue',
      );
    }
    expect(await db.select(db.reviewEvents).get(), isEmpty);
    expect(await db.select(db.reviewStates).get(), isEmpty);
  });

  test('cue replaces only its own legacy generated question', () async {
    await install();
    final questions = await db.select(db.questions).get();
    expect(
      questions
          .where((q) => q.knowledgeItemId == primary)
          .map((q) => q.questionTemplateId),
      contains(cueTemplate),
    );
    expect(
      questions
          .where((q) => q.knowledgeItemId == primary)
          .map((q) => q.questionTemplateId),
      isNot(contains(broadTemplate)),
    );
    expect(
      questions
          .where((q) => q.knowledgeItemId == advanced)
          .map((q) => q.questionTemplateId),
      contains(broadTemplate),
    );
    expect(
      questions
          .where((q) => q.knowledgeItemId == advanced)
          .map((q) => q.questionTemplateId),
      isNot(contains(cueTemplate)),
    );
    await expectLater(
      presenter.present(advanced, cueTemplate, seed: 1),
      throwsArgumentError,
    );
  });

  test('malformed cue mappings and duplicate normalized answers fail validation', () {
    for (final invalid in [
      <String, dynamic>{},
      {
        primary: {
          'prompt': '',
          'acceptedAnswers': ['slower'],
        },
      },
      {
        primary: {'prompt': cuePrompt, 'acceptedAnswers': <String>[]},
      },
      {
        primary: {
          'prompt': cuePrompt,
          'acceptedAnswers': [1],
        },
      },
      {
        primary: {
          'prompt': cuePrompt,
          'acceptedAnswers': ['slower', 'SLOWER'],
        },
      },
      {
        'not_an_item': {
          'prompt': cuePrompt,
          'acceptedAnswers': ['slower'],
        },
      },
    ]) {
      final data = pointFixture();
      final template = rowOf(data, 'question_templates', 'id', cueTemplate);
      template['parameters'] = {'item_cues': invalid};
      expect(
        validateDataset(datasetOf(data)).errors
            .where((error) => error.rule == 'template-parameters'),
        isNotEmpty,
      );
    }
    final legal = pointFixture();
    rowOf(legal, 'question_templates', 'id', cueTemplate)['relation_type'] =
        'PERMITS_PRINCIPAL_GRAPE';
    expect(
      validateDataset(datasetOf(legal)).errors
          .where((error) => error.rule == 'template-parameters'),
      isNotEmpty,
      reason:
          'scoped explanation cues cannot alter legal multiple-answer behavior',
    );
  });
}
