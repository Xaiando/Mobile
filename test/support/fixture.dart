import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';

/// A fresh in-memory database with the canonical schema.
AppDatabase openTestDatabase() => AppDatabase(NativeDatabase.memory());

/// A fixed instant used by the fixtures (UTC, whole milliseconds).
final t0 = DateTime.utc(2026, 1, 1, 9);

Future<void> runSql(AppDatabase db, List<String> statements) async {
  for (final statement in statements) {
    await db.customStatement(statement);
  }
}

/// Seeds [curriculumSeed] through the curriculum write lock.
Future<void> seedCurriculum(AppDatabase db) =>
    db.writeCurriculum(() => runSql(db, curriculumSeed));

/// Seeds scheduler configuration version 1 (FSRS-6 package defaults).
Future<void> seedSchedulerConfig(AppDatabase db) => db.customStatement(
  "INSERT INTO scheduler_configs VALUES (1, '$fsrsWeightsJson', 0.9, "
  "'[60, 600]', '[600]', 36500, 0, '2026-01-01T09:00:00.000Z')",
);

final fsrsWeightsJson = jsonEncode(fsrs.defaultParameters);

/// A small normalized curriculum slice: Chablis and Barolo, with two tracks
/// per organization, two tasting grids and generated questions.
///
/// Test data for the schema, not curated content: it carries no citations
/// beyond one placeholder and is never shipped.
const curriculumSeed = <String>[
  "INSERT INTO curriculum_releases VALUES ('0.1.0', 'sha256:test', '2026-09-24T00:00:00.000Z', '2026-09-24T00:00:00.000Z')",
  "INSERT INTO curriculum_domains VALUES ('geography', 'Geography', 1), ('viticulture', 'Viticulture', 2)",
  "INSERT INTO tasting_grids VALUES ('tg_wset_sat_l3', 'WSET_SAT', '2026.1', 'WSET Level 3 grid'), ('tg_cms_dtm_certified', 'CMS_DTM', '2026.1', 'CMS Certified grid')",
  "INSERT INTO certifications VALUES ('WSET_L1', 'WSET', 1, 'WSET Level 1', NULL, NULL, 0), ('WSET_L2', 'WSET', 2, 'WSET Level 2', 'WSET_L1', NULL, 0), ('WSET_L3', 'WSET', 3, 'WSET Level 3', 'WSET_L2', 'tg_wset_sat_l3', 1), ('CMS_INTRODUCTORY', 'CMS', 1, 'CMS Introductory', NULL, NULL, 0), ('CMS_CERTIFIED', 'CMS', 2, 'CMS Certified', 'CMS_INTRODUCTORY', 'tg_cms_dtm_certified', 1)",
  "INSERT INTO node_types VALUES ('country', 'country'), ('region', 'region'), ('appellation', 'appellation'), ('grape', 'grape variety'), ('berry_colour', 'berry colour'), ('soil', 'soil'), ('quantity', 'quantity')",
  "INSERT INTO relation_types VALUES ('LOCATED_IN', 'is located in', 'contains', 'many', 1, 0, 'geography', NULL), ('HAS_BERRY_COLOUR', 'has berry colour', 'is the berry colour of', 'one', 0, 0, 'viticulture', NULL), ('PERMITS_PRINCIPAL_GRAPE', 'permits the principal grape', 'is a principal grape of', 'many', 0, 0, 'geography', 'HAS_BERRY_COLOUR'), ('HAS_SOIL', 'has soil', 'is the soil of', 'many', 0, 0, 'viticulture', NULL), ('MIN_AGEING', 'requires minimum ageing of', 'is the minimum ageing of', 'one', 0, 0, 'geography', NULL)",
  "INSERT INTO relation_type_signatures VALUES ('LOCATED_IN', 'appellation', 'region'), ('LOCATED_IN', 'region', 'country'), ('HAS_BERRY_COLOUR', 'grape', 'berry_colour'), ('PERMITS_PRINCIPAL_GRAPE', 'appellation', 'grape'), ('HAS_SOIL', 'appellation', 'soil'), ('MIN_AGEING', 'appellation', 'quantity')",
  "INSERT INTO knowledge_nodes (id, node_type, name, name_norm) VALUES ('n_geo_france', 'country', 'France', 'france'), ('n_geo_burgundy', 'region', 'Burgundy', 'burgundy'), ('n_geo_chablis', 'appellation', 'Chablis', 'chablis'), ('n_geo_gevrey', 'appellation', 'Gevrey-Chambertin', 'gevrey chambertin'), ('n_geo_piedmont', 'region', 'Piedmont', 'piedmont'), ('n_geo_barolo', 'appellation', 'Barolo', 'barolo'), ('n_geo_italy', 'country', 'Italy', 'italy'), ('n_grape_chardonnay', 'grape', 'Chardonnay', 'chardonnay'), ('n_grape_pinot_noir', 'grape', 'Pinot Noir', 'pinot noir'), ('n_grape_sauvignon_blanc', 'grape', 'Sauvignon Blanc', 'sauvignon blanc'), ('n_grape_chenin_blanc', 'grape', 'Chenin Blanc', 'chenin blanc'), ('n_grape_nebbiolo', 'grape', 'Nebbiolo', 'nebbiolo'), ('n_colour_white', 'berry_colour', 'White', 'white'), ('n_colour_black', 'berry_colour', 'Black', 'black'), ('n_soil_kimmeridgian', 'soil', 'Kimmeridgian marl', 'kimmeridgian marl'), ('n_qty_38_months', 'quantity', '38 months', '38 months')",
  "INSERT INTO quantity_values (knowledge_node_id, minimum, unit) VALUES ('n_qty_38_months', 38, 'month')",
  "INSERT INTO node_alternative_names VALUES ('n_grape_chardonnay', 'Beaunois', 'beaunois', 'synonym')",
  "INSERT INTO knowledge_relations VALUES ('n_geo_burgundy', 'LOCATED_IN', 'n_geo_france', '1936-01-01', NULL), ('n_geo_chablis', 'LOCATED_IN', 'n_geo_burgundy', '1938-01-13', NULL), ('n_geo_gevrey', 'LOCATED_IN', 'n_geo_burgundy', '1936-09-11', NULL), ('n_geo_piedmont', 'LOCATED_IN', 'n_geo_italy', '1966-01-01', NULL), ('n_geo_barolo', 'LOCATED_IN', 'n_geo_piedmont', '1966-01-01', NULL), ('n_grape_chardonnay', 'HAS_BERRY_COLOUR', 'n_colour_white', '1900-01-01', NULL), ('n_grape_sauvignon_blanc', 'HAS_BERRY_COLOUR', 'n_colour_white', '1900-01-01', NULL), ('n_grape_chenin_blanc', 'HAS_BERRY_COLOUR', 'n_colour_white', '1900-01-01', NULL), ('n_grape_pinot_noir', 'HAS_BERRY_COLOUR', 'n_colour_black', '1900-01-01', NULL), ('n_geo_chablis', 'PERMITS_PRINCIPAL_GRAPE', 'n_grape_chardonnay', '1938-01-13', NULL), ('n_geo_gevrey', 'PERMITS_PRINCIPAL_GRAPE', 'n_grape_pinot_noir', '1936-09-11', NULL), ('n_geo_chablis', 'HAS_SOIL', 'n_soil_kimmeridgian', '1938-01-13', NULL), ('n_geo_barolo', 'MIN_AGEING', 'n_qty_38_months', '1980-01-01', NULL)",
  "INSERT INTO knowledge_items (id, subject_id, relation_type, object_id, domain_id, assertion_text, last_verified_at) VALUES ('ki_chablis_grape', 'n_geo_chablis', 'PERMITS_PRINCIPAL_GRAPE', 'n_grape_chardonnay', 'geography', 'Chardonnay is the only principal grape variety permitted in the Chablis AOC.', '2026-09-24T00:00:00.000Z'), ('ki_chablis_soil', 'n_geo_chablis', 'HAS_SOIL', 'n_soil_kimmeridgian', 'viticulture', 'The premier and grand cru vineyards of Chablis lie on Kimmeridgian marl.', '2026-09-24T00:00:00.000Z'), ('ki_barolo_min_ageing', 'n_geo_barolo', 'MIN_AGEING', 'n_qty_38_months', 'geography', 'Barolo DOCG requires at least 38 months of ageing.', '2026-09-24T00:00:00.000Z')",
  "INSERT INTO knowledge_item_prerequisites VALUES ('ki_chablis_soil', 'ki_chablis_grape')",
  "INSERT INTO certification_knowledge_mappings VALUES ('WSET_L2', 'ki_chablis_grape', 'core', 1, NULL), ('CMS_CERTIFIED', 'ki_chablis_grape', 'core', 2, NULL), ('WSET_L3', 'ki_chablis_soil', 'core', 2, NULL)",
  "INSERT INTO source_citations (id, kind, title, publisher, jurisdiction, accessed_on) VALUES ('src_inao_chablis', 'legislation', 'Cahier des charges de l''appellation d''origine contrôlée « Chablis »', 'INAO', 'FR', '2026-09-24')",
  "INSERT INTO knowledge_item_citations VALUES ('ki_chablis_grape', 'src_inao_chablis', NULL)",
  "INSERT INTO question_templates VALUES ('qt_ppg_fwd_mcq', 'PERMITS_PRINCIPAL_GRAPE', 'forward', 'mcq', 'en', 'Which grape variety is the principal grape of {subject.name}?'), ('qt_soil_fwd_flashcard', 'HAS_SOIL', 'forward', 'flashcard', 'en', 'What is the characteristic soil of {subject.name}?')",
  "INSERT INTO tasting_grid_attributes VALUES ('tg_wset_sat_l3', 'sweetness', 'palate', 'Sweetness', 1, 'single', 1), ('tg_wset_sat_l3', 'primary_aromas', 'nose', 'Primary aromas', 2, 'multi', 0), ('tg_cms_dtm_certified', 'fruit_condition', 'nose', 'Fruit condition', 1, 'single', 1)",
  "INSERT INTO tasting_grid_values VALUES ('tg_wset_sat_l3', 'sweetness', 'dry', 'dry', 1, NULL), ('tg_wset_sat_l3', 'sweetness', 'off_dry', 'off-dry', 2, NULL), ('tg_wset_sat_l3', 'primary_aromas', 'lemon', 'lemon', 1, NULL), ('tg_wset_sat_l3', 'primary_aromas', 'green_apple', 'green apple', 2, NULL), ('tg_cms_dtm_certified', 'fruit_condition', 'tart', 'tart', 1, NULL)",
  "INSERT INTO questions VALUES ('ki_chablis_grape', 'qt_ppg_fwd_mcq', 'PERMITS_PRINCIPAL_GRAPE', 'Which grape variety is the principal grape of Chablis?'), ('ki_chablis_soil', 'qt_soil_fwd_flashcard', 'HAS_SOIL', 'What is the characteristic soil of Chablis?')",
  "INSERT INTO question_distractors VALUES ('ki_chablis_grape', 'qt_ppg_fwd_mcq', 'n_grape_sauvignon_blanc', 1), ('ki_chablis_grape', 'qt_ppg_fwd_mcq', 'n_grape_chenin_blanc', 1), ('ki_chablis_grape', 'qt_ppg_fwd_mcq', 'n_grape_pinot_noir', 0)",
];

/// The last two seed statements: the generated question tables.
List<String> get generatedQuestionSeed =>
    curriculumSeed.sublist(curriculumSeed.length - 2);
