import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/coverage/track_scope.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final lessons = dataset.knowledgeItems.where(
    (item) =>
        item.id.startsWith('ki_cms_beer_') ||
        item.id.startsWith('ki_cms_cider_') ||
        item.id.startsWith('ki_cms_belgian_'),
  );

  test('CMS beer and cider closure is cited and stays off WSET tracks', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(lessons, hasLength(33));
    for (final item in lessons) {
      expect(item.domainId, 'service', reason: item.id);
      expect(item.verificationStatus, 'unverified', reason: item.id);
      expect(item.mcqDisabled, isTrue, reason: item.id);
      expect(
        dataset.knowledgeItemCitations.any(
          (citation) => citation.knowledgeItemId == item.id,
        ),
        isTrue,
        reason: item.id,
      );
      final tracks = dataset.certificationKnowledgeMappings
          .where((mapping) => mapping.knowledgeItemId == item.id)
          .map((mapping) => mapping.certificationId)
          .toSet();
      expect(tracks, {'CMS_CERTIFIED'}, reason: item.id);
    }
  });

  test(
    'Introductory production and Certified pairing/Belgian scope are selected',
    () {
      final manifest = TrackScopeManifest.parse(
        File('assets/curriculum/track_scope.yaml').readAsStringSync(),
      );
      final beer = manifest.tracks['CMS_CERTIFIED']!.objectives.singleWhere(
        (objective) => objective.id == 'cms_certified.beer_and_cider',
      );
      expect(
        beer.covers!.within,
        containsAll({
          'n_cms_beer_brewhouse',
          'n_cms_beer_style_compare',
          'n_cms_beer_condition',
          'n_cms_cider_process',
          'n_cms_belgian_styles',
          'n_cms_beer_food',
          'n_cms_beer_case_cask',
          'n_cms_beer_case_pair',
          'n_cms_beer_case_belgian',
        }),
      );
    },
  );

  test(
    'three authored service cases have all four criteria and question prompts',
    () {
      for (final subject in [
        'n_cms_beer_case_cask',
        'n_cms_beer_case_pair',
        'n_cms_beer_case_belgian',
      ]) {
        expect(
          lessons
              .where((item) => item.subjectId == subject)
              .map((item) => item.relationType)
              .toSet(),
          {'CASE_ACTION', 'CASE_REASON', 'CASE_TRADEOFF', 'CASE_LIMITATION'},
          reason: subject,
        );
      }
      final templates = dataset.questionTemplates.where(
        (template) => template.id.startsWith('qt_cms_beer_case_'),
      );
      expect(templates, hasLength(3));
      for (final template in templates) {
        expect(template.mode, 'short_answer');
        expect(template.parameters, contains('CASE_LIMITATION'));
      }
    },
  );

  test(
    'critical beverage distinctions are taught without formula shortcuts',
    () {
      final facts = {for (final item in lessons) item.id: item.assertionText};
      expect(facts['ki_cms_beer_wort'], contains('before'));
      expect(facts['ki_cms_beer_cask_terms'], contains('Stillage'));
      expect(facts['ki_cms_beer_package'], contains('does not by itself'));
      expect(facts['ki_cms_cider_style'], contains('not legal names'));
      expect(facts['ki_cms_belgian_dubbel_tripel'], contains('not a simple'));
      expect(facts['ki_cms_beer_food_trial'], contains('not absolute rules'));
    },
  );

  test('Irish whiskey and liqueur examples stay CMS-only and cited', () {
    final extensions = dataset.knowledgeItems.where(
      (item) =>
          item.id.startsWith('ki_cms_irish_') ||
          item.id.startsWith('ki_cms_liqueur_'),
    );
    expect(extensions, hasLength(14));
    for (final item in extensions) {
      expect(item.verificationStatus, 'unverified', reason: item.id);
      expect(item.mcqDisabled, isTrue, reason: item.id);
      expect(
        dataset.knowledgeItemCitations.any(
          (citation) => citation.knowledgeItemId == item.id,
        ),
        isTrue,
        reason: item.id,
      );
      expect(
        dataset.certificationKnowledgeMappings
            .where((mapping) => mapping.knowledgeItemId == item.id)
            .map((mapping) => mapping.certificationId)
            .toSet(),
        {'CMS_CERTIFIED'},
        reason: item.id,
      );
    }
    final manifest = TrackScopeManifest.parse(
      File('assets/curriculum/track_scope.yaml').readAsStringSync(),
    );
    final objectives = manifest.tracks['CMS_CERTIFIED']!.objectives;
    expect(
      objectives
          .singleWhere((objective) => objective.id == 'cms_certified.spirits')
          .covers!
          .within,
      containsAll({'n_cms_irish_whiskey', 'n_cms_irish_case'}),
    );
    expect(
      objectives
          .singleWhere(
            (objective) =>
                objective.id == 'cms_certified.liqueurs_and_aperitifs',
          )
          .covers!
          .within,
      containsAll({'n_cms_liqueur_extraction', 'n_cms_liqueur_case'}),
    );
    expect(
      dataset.questionTemplates.where(
        (template) =>
            template.id == 'qt_cms_irish_case' ||
            template.id == 'qt_cms_liqueur_case',
      ),
      hasLength(2),
    );
  });
}
