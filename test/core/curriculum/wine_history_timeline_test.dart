import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/questions/formats/short_answer/short_answer_format.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  final dataset = bundledDataset();
  const principleId = 'ki_htime_greek_symposium_krater';
  const caseSubject = 'n_htime_case_greek_roman_vessels';
  const caseRoles = [
    'CASE_ACTION',
    'CASE_REASON',
    'CASE_TRADEOFF',
    'CASE_LIMITATION',
  ];
  const greekSourceId = 'src_htime_met_greek_krater';
  const romanSourceId = 'src_htime_met_amphora';

  test(
    'Greek milestone and vessel case have cited facts on both upper tracks',
    () {
      final greekSource = dataset.sourceCitations.singleWhere(
        (source) => source.id == greekSourceId,
      );
      expect(
        greekSource.url,
        'https://www.metmuseum.org/art/collection/search/253349',
      );
      final greekItem = dataset.knowledgeItems.singleWhere(
        (item) => item.id == principleId,
      );
      expect(greekItem.assertionText, contains('about 550 BCE'));
      expect(greekItem.assertionText, contains('Greek symposium'));
      expect(greekItem.subjectId, 'n_htime_greek_symposium');
      expect(
        dataset.knowledgeItemCitations
            .where((citation) => citation.knowledgeItemId == principleId)
            .map((citation) => citation.sourceCitationId)
            .toSet(),
        {greekSourceId},
      );

      final caseItems = dataset.knowledgeItems
          .where((item) => item.subjectId == caseSubject)
          .toList();
      expect(caseItems, hasLength(4));
      expect(caseItems.map((item) => item.relationType).toList(), caseRoles);
      for (final item in [greekItem, ...caseItems]) {
        expect(item.domainId, 'service', reason: item.id);
        expect(item.verificationStatus, 'unverified', reason: item.id);
        expect(item.mcqDisabled, isTrue, reason: item.id);
        final mappings = dataset.certificationKnowledgeMappings
            .where((mapping) => mapping.knowledgeItemId == item.id)
            .toList();
        expect(mappings.map((mapping) => mapping.certificationId).toSet(), {
          'CMS_CERTIFIED',
          'WSET_L4',
        }, reason: item.id);
        for (final mapping in mappings) {
          expect(mapping.importance, 'secondary', reason: item.id);
          expect(mapping.minimumDepth, 2, reason: item.id);
        }
        expect(
          dataset.knowledgeRelations.any(
            (relation) =>
                relation.subjectId == item.subjectId &&
                relation.relationType == item.relationType &&
                relation.objectId == item.objectId,
          ),
          isTrue,
          reason: item.id,
        );
      }
      for (final item in caseItems) {
        expect(
          dataset.knowledgeItemCitations
              .where((citation) => citation.knowledgeItemId == item.id)
              .map((citation) => citation.sourceCitationId)
              .toSet(),
          {greekSourceId, romanSourceId},
          reason: item.id,
        );
      }
      expect(
        dataset.knowledgeNodes
            .singleWhere((node) => node.id == 'n_hcourse_case_repeal_limit')
            .name,
        'The later law is cited separately',
      );
    },
  );

  test(
    'Greek and Roman vessels generate a four-point short-answer case',
    () async {
      final template = dataset.questionTemplates.singleWhere(
        (template) => template.id == 'qt_hist_case_greek_roman_vessels',
      );
      expect(template.mode, 'short_answer');
      expect(template.relationType, 'CASE_ACTION');
      expect(template.direction, 'forward');
      expect(ShortAnswerFormat.scopeNodeIdsOf(template), {caseSubject});
      expect(ShortAnswerFormat.keyPointsOf(template)!.keys.toList(), caseRoles);
      expect(template.promptTemplate, contains('Greek krater'));
      expect(template.promptTemplate, contains('Roman amphora'));

      final db = openTestDatabase();
      addTearDown(db.close);
      await CurriculumIngester(db).ingest(dataset);
      final pool = (await db.select(db.exercisePools).get()).singleWhere(
        (pool) => pool.questionTemplateId == template.id,
      );
      expect(pool.scopeNodeId, caseSubject);
      expect(pool.promptText, template.promptTemplate);
      final members = await db.select(db.exercisePoolItems).get();
      expect(
        members
            .where((member) => member.exercisePoolId == pool.id)
            .map((member) => member.knowledgeItemId)
            .toSet(),
        {
          'ki_htime_case_greek_roman_vessels_action',
          'ki_htime_case_greek_roman_vessels_reason',
          'ki_htime_case_greek_roman_vessels_tradeoff',
          'ki_htime_case_greek_roman_vessels_limit',
        },
      );
    },
  );
}
