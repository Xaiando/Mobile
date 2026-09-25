import 'package:clock/clock.dart';
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_model.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

/// The date the coverage fixture is measured on: its release date.
const coverageDate = '2026-01-01';

/// The policy of [coverageDataset]: France is split into regions, Germany
/// is not.
const coveragePolicyText = '''
regional_countries: [n_geo_france]
capabilities:
  LOCATED_IN:
    supports: [flashcard, mcq]
  HAS_BERRY_COLOUR:
    excludes:
      flashcard: Structural in this fixture.
      mcq: Structural in this fixture.
  PERMITS_PRINCIPAL_GRAPE:
    supports: [flashcard, mcq]
  SUSCEPTIBLE_TO:
    supports: [flashcard, mcq]
thresholds:
  all:
    core_flashcard_only: {max: 0}
    core_useful_practice: {min: 90%}
  domains:
    viticulture:
      core_reasoning: {min: 50%}
''';

/// A release whose coverage is known item by item. On WSET_L2:
///
/// | Item | Mapping | Questions | Served |
/// |---|---|---|---|
/// | ki_chablis_grape | core, depth 2 | MCQ, flashcard | both |
/// | ki_volnay_grape | core, depth 1 | MCQ, flashcard | MCQ |
/// | ki_meursault_grape | core, depth 2, mcq_disabled | flashcard | flashcard |
/// | ki_pommard_grape | secondary, depth 2, mcq_disabled | flashcard | flashcard |
/// | ki_pommard_gamay | core; its relation ended in 1937 | none | not counted |
/// | ki_morgon_grape | core, depth 3 | MCQ, flashcard | both |
/// | ki_walporzheim_grape | WSET_L1: core, depth 2 | MCQ, flashcard | both |
/// | ki_cool_frost | core, depth 2 | none: too few hazards | none |
///
/// Reverse flashcards are skipped: the grape relation is not reverse-safe.
/// On CMS_CERTIFIED: ki_chablis_grape at depth 1, and ki_meursault_grape as
/// secondary, through CMS_INTRODUCTORY.
Map<String, dynamic> coverageDataset() => {
  'dataset_version': '1.0.0',
  'published_at': '2026-01-01T00:00:00.000Z',
  'curriculum_domains': [
    {'id': 'geography', 'display_name': 'Geography', 'position': 1},
    {'id': 'viticulture', 'display_name': 'Viticulture', 'position': 2},
  ],
  'certifications': [
    _track('WSET_L1', 'WSET', 1),
    _track('WSET_L2', 'WSET', 2, includes: 'WSET_L1', selectable: true),
    _track('CMS_INTRODUCTORY', 'CMS', 1),
    _track(
      'CMS_CERTIFIED',
      'CMS',
      2,
      includes: 'CMS_INTRODUCTORY',
      selectable: true,
    ),
  ],
  'node_types': [
    for (final (id, label) in [
      ('country', 'country'),
      ('region', 'region'),
      ('appellation', 'appellation'),
      ('grape', 'grape variety'),
      ('berry_colour', 'berry colour'),
      ('climate', 'climate'),
      ('hazard', 'vineyard hazard'),
    ])
      {'id': id, 'label': label},
  ],
  'relation_types': [
    _relationType('LOCATED_IN', 'is located in', 'contains', transitive: true),
    _relationType('HAS_BERRY_COLOUR', 'has berry colour', 'is the colour of'),
    {
      ..._relationType(
        'PERMITS_PRINCIPAL_GRAPE',
        'permits the principal grape',
        'is a principal grape of',
      ),
      'distractor_match_relation_type': 'HAS_BERRY_COLOUR',
    },
    _relationType('SUSCEPTIBLE_TO', 'is susceptible to', 'threatens'),
  ],
  'relation_type_signatures': [
    for (final (type, subject, object) in [
      ('LOCATED_IN', 'appellation', 'region'),
      ('LOCATED_IN', 'region', 'country'),
      ('HAS_BERRY_COLOUR', 'grape', 'berry_colour'),
      ('PERMITS_PRINCIPAL_GRAPE', 'appellation', 'grape'),
      ('SUSCEPTIBLE_TO', 'climate', 'hazard'),
    ])
      {
        'relation_type': type,
        'subject_node_type': subject,
        'object_node_type': object,
      },
  ],
  'knowledge_nodes': [
    for (final (id, type, name) in [
      ('n_geo_france', 'country', 'France'),
      ('n_geo_burgundy', 'region', 'Burgundy'),
      ('n_geo_beaujolais', 'region', 'Beaujolais'),
      ('n_geo_chablis', 'appellation', 'Chablis'),
      ('n_geo_volnay', 'appellation', 'Volnay'),
      ('n_geo_meursault', 'appellation', 'Meursault'),
      ('n_geo_pommard', 'appellation', 'Pommard'),
      ('n_geo_morgon', 'appellation', 'Morgon'),
      ('n_geo_germany', 'country', 'Germany'),
      ('n_geo_ahr', 'region', 'Ahr'),
      ('n_geo_walporzheim', 'appellation', 'Walporzheim'),
      ('n_grape_chardonnay', 'grape', 'Chardonnay'),
      ('n_grape_aligote', 'grape', 'Aligoté'),
      ('n_grape_sauvignon_blanc', 'grape', 'Sauvignon Blanc'),
      ('n_grape_chenin_blanc', 'grape', 'Chenin Blanc'),
      ('n_grape_pinot_noir', 'grape', 'Pinot Noir'),
      ('n_grape_gamay', 'grape', 'Gamay'),
      ('n_grape_syrah', 'grape', 'Syrah'),
      ('n_grape_merlot', 'grape', 'Merlot'),
      ('n_colour_white', 'berry_colour', 'White'),
      ('n_colour_black', 'berry_colour', 'Black'),
      ('n_climate_cool', 'climate', 'Cool climate'),
      ('n_hazard_spring_frost', 'hazard', 'Spring frost'),
      ('n_hazard_hail', 'hazard', 'Hail'),
    ])
      {'id': id, 'node_type': type, 'name': name},
  ],
  'quantity_values': <dynamic>[],
  'node_alternative_names': <dynamic>[],
  'knowledge_relations': [
    for (final (subject, object) in [
      ('n_geo_burgundy', 'n_geo_france'),
      ('n_geo_beaujolais', 'n_geo_france'),
      ('n_geo_chablis', 'n_geo_burgundy'),
      ('n_geo_volnay', 'n_geo_burgundy'),
      ('n_geo_meursault', 'n_geo_burgundy'),
      ('n_geo_pommard', 'n_geo_burgundy'),
      ('n_geo_morgon', 'n_geo_beaujolais'),
      ('n_geo_ahr', 'n_geo_germany'),
      ('n_geo_walporzheim', 'n_geo_ahr'),
    ])
      _relation(subject, 'LOCATED_IN', object),
    for (final grape in [
      'chardonnay',
      'aligote',
      'sauvignon_blanc',
      'chenin_blanc',
    ])
      _relation('n_grape_$grape', 'HAS_BERRY_COLOUR', 'n_colour_white'),
    for (final grape in ['pinot_noir', 'gamay', 'syrah', 'merlot'])
      _relation('n_grape_$grape', 'HAS_BERRY_COLOUR', 'n_colour_black'),
    for (final (subject, object) in [
      ('n_geo_chablis', 'n_grape_chardonnay'),
      ('n_geo_volnay', 'n_grape_pinot_noir'),
      ('n_geo_meursault', 'n_grape_chardonnay'),
      ('n_geo_pommard', 'n_grape_pinot_noir'),
      ('n_geo_morgon', 'n_grape_gamay'),
      ('n_geo_walporzheim', 'n_grape_pinot_noir'),
    ])
      _relation(subject, 'PERMITS_PRINCIPAL_GRAPE', object),
    {
      ..._relation('n_geo_pommard', 'PERMITS_PRINCIPAL_GRAPE', 'n_grape_gamay'),
      'valid_until': '1937-01-01',
    },
    _relation('n_climate_cool', 'SUSCEPTIBLE_TO', 'n_hazard_spring_frost'),
  ],
  'knowledge_items': [
    _item('ki_chablis_grape', 'n_geo_chablis', 'n_grape_chardonnay'),
    _item('ki_volnay_grape', 'n_geo_volnay', 'n_grape_pinot_noir'),
    {
      ..._item('ki_meursault_grape', 'n_geo_meursault', 'n_grape_chardonnay'),
      'mcq_disabled': true,
    },
    {
      ..._item('ki_pommard_grape', 'n_geo_pommard', 'n_grape_pinot_noir'),
      'mcq_disabled': true,
    },
    _item('ki_pommard_gamay', 'n_geo_pommard', 'n_grape_gamay'),
    _item('ki_morgon_grape', 'n_geo_morgon', 'n_grape_gamay'),
    _item('ki_walporzheim_grape', 'n_geo_walporzheim', 'n_grape_pinot_noir'),
    {
      ..._item('ki_cool_frost', 'n_climate_cool', 'n_hazard_spring_frost'),
      'relation_type': 'SUSCEPTIBLE_TO',
      'domain_id': 'viticulture',
    },
  ],
  'knowledge_item_prerequisites': <dynamic>[],
  'certification_knowledge_mappings': [
    _mapping('WSET_L2', 'ki_chablis_grape', 'core', 2),
    _mapping('WSET_L2', 'ki_volnay_grape', 'core', 1),
    _mapping('WSET_L2', 'ki_meursault_grape', 'core', 2),
    _mapping('WSET_L2', 'ki_pommard_grape', 'secondary', 2),
    _mapping('WSET_L2', 'ki_pommard_gamay', 'core', 2),
    _mapping('WSET_L2', 'ki_morgon_grape', 'core', 3),
    _mapping('WSET_L1', 'ki_walporzheim_grape', 'core', 2),
    _mapping('WSET_L2', 'ki_cool_frost', 'core', 2),
    _mapping('CMS_CERTIFIED', 'ki_chablis_grape', 'core', 1),
    _mapping('CMS_INTRODUCTORY', 'ki_meursault_grape', 'secondary', 2),
  ],
  'source_citations': [
    {
      'id': 'src_test_law',
      'kind': 'legislation',
      'title': 'A test cahier des charges',
      'publisher': 'Test publisher',
      'accessed_on': '2026-01-01',
    },
  ],
  'knowledge_item_citations': [
    for (final item in [
      'ki_chablis_grape',
      'ki_volnay_grape',
      'ki_meursault_grape',
      'ki_pommard_grape',
      'ki_pommard_gamay',
      'ki_morgon_grape',
      'ki_walporzheim_grape',
      'ki_cool_frost',
    ])
      {'knowledge_item_id': item, 'source_citation_id': 'src_test_law'},
  ],
  'question_templates': [
    _template('qt_grape_fwd_flashcard', 'PERMITS_PRINCIPAL_GRAPE', 'flashcard'),
    _template('qt_grape_fwd_mcq', 'PERMITS_PRINCIPAL_GRAPE', 'mcq'),
    _template(
      'qt_grape_rev_flashcard',
      'PERMITS_PRINCIPAL_GRAPE',
      'flashcard',
      direction: 'reverse',
    ),
    _template('qt_hazard_fwd_mcq', 'SUSCEPTIBLE_TO', 'mcq'),
  ],
  'tasting_grids': <dynamic>[],
  'tasting_grid_attributes': <dynamic>[],
  'tasting_grid_values': <dynamic>[],
};

/// Ingests [dataset] for [coverageDate] and measures [track] under [policy].
Future<TrackCoverage> coverageOf(
  Map<String, dynamic> dataset, {
  String track = 'WSET_L2',
  String policy = coveragePolicyText,
}) async =>
    (await coverageOfTracks(dataset, tracks: [track], policy: policy)).single;

/// [coverageOf] for several tracks: every selectable one by default.
Future<List<TrackCoverage>> coverageOfTracks(
  Map<String, dynamic> dataset, {
  List<String>? tracks,
  String policy = coveragePolicyText,
}) async {
  final db = openTestDatabase();
  // The results hold no database, so it closes before the next one opens.
  try {
    final generation = await CurriculumIngester(
      db,
      clock: Clock.fixed(DateTime(2026, 1, 1, 12)),
    ).ingest(datasetOf(dataset));
    final checker = CoverageChecker(db, CoveragePolicy.parse(policy));
    return [
      for (final track
          in tracks ?? [for (final t in await checker.selectableTracks()) t.id])
        await checker.check(
          track,
          on: coverageDate,
          skipped: generation.skipped,
        ),
    ];
  } finally {
    await db.close();
  }
}

/// The mapping row of [item] on [track] in [dataset], for changing it.
Map<String, dynamic> mappingOf(
  Map<String, dynamic> dataset,
  String track,
  String item,
) => rowsOf(dataset, 'certification_knowledge_mappings')
    .cast<Map<String, dynamic>>()
    .firstWhere(
      (m) => m['certification_id'] == track && m['knowledge_item_id'] == item,
    );

Map<String, dynamic> _track(
  String id,
  String organization,
  int level, {
  String? includes,
  bool selectable = false,
}) => {
  'id': id,
  'organization': organization,
  'level': level,
  'display_name': '$organization level $level',
  'includes_certification_id': ?includes,
  if (selectable) 'is_selectable': true,
};

Map<String, dynamic> _relationType(
  String id,
  String label,
  String reverse, {
  bool transitive = false,
}) => {
  'id': id,
  'label': label,
  'reverse_label': reverse,
  'cardinality': 'many',
  'is_transitive': transitive,
  'default_domain_id': 'geography',
};

Map<String, dynamic> _relation(String subject, String type, String object) => {
  'subject_id': subject,
  'relation_type': type,
  'object_id': object,
  'valid_from': '1900-01-01',
};

Map<String, dynamic> _item(String id, String subject, String object) => {
  'id': id,
  'subject_id': subject,
  'relation_type': 'PERMITS_PRINCIPAL_GRAPE',
  'object_id': object,
  'domain_id': 'geography',
  'assertion_text': 'A test assertion.',
  'last_verified_at': '2026-01-01T00:00:00.000Z',
};

Map<String, dynamic> _mapping(
  String track,
  String item,
  String importance,
  int depth,
) => {
  'certification_id': track,
  'knowledge_item_id': item,
  'importance': importance,
  'minimum_depth': depth,
};

Map<String, dynamic> _template(
  String id,
  String relationType,
  String mode, {
  String direction = 'forward',
}) => {
  'id': id,
  'relation_type': relationType,
  'direction': direction,
  'mode': mode,
  'prompt_template': 'What about {subject.name}?',
};
