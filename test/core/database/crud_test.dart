import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';

import '../../support/fixture.dart';

/// Phase 0 acceptance: basic CRUD works on every table of the schema.
///
/// Each case creates a fresh row on top of the fixture, reads it, updates it
/// and deletes it. Curriculum tables do this inside the write lock; the
/// append-only review log must reject updates and deletes.
enum Scope { curriculum, user, system }

class CrudCase {
  const CrudCase(
    this.table, {
    required this.scope,
    required this.create,
    required this.where,
    required this.update,
    required this.whereUpdated,
    required this.delete,
    this.appendOnly = false,
  });

  final String table;
  final Scope scope;
  final List<String> create;
  final String where;
  final String update;
  final String whereUpdated;
  final List<String> delete;
  final bool appendOnly;
}

const _ts = "'2026-01-01T09:00:00.000Z'";

String _uuid(int n) =>
    "'00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}'";

String _event(int n) =>
    'INSERT INTO review_events (id, knowledge_item_id, question_template_id, '
    'reviewed_at, rating, scheduler_config_version, state_after, step_after, '
    'stability_after, difficulty_after, due_after) VALUES (${_uuid(n)}, '
    "'ki_chablis_grape', 'qt_ppg_fwd_mcq', $_ts, 3, 1, 1, 1, 2.3, 5.0, "
    "'2026-01-01T09:10:00.000Z')";

String _journal(int n) =>
    'INSERT INTO wine_journal_entries (id, producer_name, vintage, created_at, '
    "updated_at) VALUES (${_uuid(n)}, 'Example Producer', 2019, $_ts, $_ts)";

String _session(int n) =>
    'INSERT INTO tasting_sessions (id, tasting_grid_id, started_at) '
    "VALUES (${_uuid(n)}, 'tg_wset_sat_l3', $_ts)";

/// A map layer [id], drawn from a placeholder asset.
String _layer(String id) =>
    "INSERT INTO map_layers VALUES ('$id', 'Test layer', 'area', "
    "'assets/geography/$id.topo.json', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 4, 10, NULL)";

final cases = <CrudCase>[
  // ---- Curriculum, authored ------------------------------------------------
  const CrudCase(
    'curriculum_releases',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO curriculum_releases VALUES ('0.2.0', 'sha256:crud', $_ts, $_ts)",
    ],
    where: "version = '0.2.0'",
    update: "UPDATE curriculum_releases SET checksum = 'sha256:changed' WHERE version = '0.2.0'",
    whereUpdated: "version = '0.2.0' AND checksum = 'sha256:changed'",
    delete: ["DELETE FROM curriculum_releases WHERE version = '0.2.0'"],
  ),
  const CrudCase(
    'curriculum_domains',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO curriculum_domains VALUES ('winemaking', 'Winemaking', 3)",
    ],
    where: "id = 'winemaking'",
    update: "UPDATE curriculum_domains SET display_name = 'Winemaking and maturation' WHERE id = 'winemaking'",
    whereUpdated: "display_name = 'Winemaking and maturation'",
    delete: ["DELETE FROM curriculum_domains WHERE id = 'winemaking'"],
  ),
  const CrudCase(
    'tasting_grids',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO tasting_grids VALUES ('tg_crud', 'WSET_SAT', '2027.1', 'Draft grid')",
    ],
    where: "id = 'tg_crud'",
    update: "UPDATE tasting_grids SET display_name = 'Renamed grid' WHERE id = 'tg_crud'",
    whereUpdated: "display_name = 'Renamed grid'",
    delete: ["DELETE FROM tasting_grids WHERE id = 'tg_crud'"],
  ),
  const CrudCase(
    'certifications',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO certifications VALUES ('WSET_L4', 'WSET', 4, 'WSET Level 4', 'WSET_L3', NULL, 0, 'certification', NULL)",
    ],
    where: "id = 'WSET_L4'",
    update: "UPDATE certifications SET display_name = 'WSET Level 4, renamed' WHERE id = 'WSET_L4'",
    whereUpdated: "display_name = 'WSET Level 4, renamed'",
    delete: ["DELETE FROM certifications WHERE id = 'WSET_L4'"],
  ),
  const CrudCase(
    'node_types',
    scope: Scope.curriculum,
    create: ["INSERT INTO node_types VALUES ('hazard', 'hazard')"],
    where: "id = 'hazard'",
    update:
        "UPDATE node_types SET label = 'weather hazard' WHERE id = 'hazard'",
    whereUpdated: "label = 'weather hazard'",
    delete: ["DELETE FROM node_types WHERE id = 'hazard'"],
  ),
  const CrudCase(
    'relation_types',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO relation_types VALUES ('SUSCEPTIBLE_TO', 'is susceptible to', 'threatens', 'many', 0, 0, 'viticulture', NULL, 0)",
    ],
    where: "id = 'SUSCEPTIBLE_TO'",
    update: "UPDATE relation_types SET label = 'is prone to' WHERE id = 'SUSCEPTIBLE_TO'",
    whereUpdated: "label = 'is prone to'",
    delete: ["DELETE FROM relation_types WHERE id = 'SUSCEPTIBLE_TO'"],
  ),
  const CrudCase(
    'relation_type_signatures',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO relation_type_signatures VALUES ('HAS_SOIL', 'region', 'soil')",
    ],
    where: "relation_type = 'HAS_SOIL' AND subject_node_type = 'region'",
    update: "UPDATE relation_type_signatures SET subject_node_type = 'country' WHERE relation_type = 'HAS_SOIL' AND subject_node_type = 'region'",
    whereUpdated:
        "relation_type = 'HAS_SOIL' AND subject_node_type = 'country'",
    delete: [
      "DELETE FROM relation_type_signatures WHERE relation_type = 'HAS_SOIL' AND subject_node_type = 'country'",
    ],
  ),
  const CrudCase(
    'knowledge_nodes',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO knowledge_nodes (id, node_type, name, name_norm) VALUES ('n_grape_syrah', 'grape', 'Syrah', 'syrah')",
    ],
    where: "id = 'n_grape_syrah'",
    update: "UPDATE knowledge_nodes SET name = 'Syrah (Shiraz)' WHERE id = 'n_grape_syrah'",
    whereUpdated: "name = 'Syrah (Shiraz)'",
    delete: ["DELETE FROM knowledge_nodes WHERE id = 'n_grape_syrah'"],
  ),
  const CrudCase(
    'quantity_values',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO knowledge_nodes (id, node_type, name, name_norm) VALUES ('n_qty_26_months', 'quantity', '26 months', '26 months')",
      "INSERT INTO quantity_values (knowledge_node_id, minimum, unit) VALUES ('n_qty_26_months', 26, 'month')",
    ],
    where: "knowledge_node_id = 'n_qty_26_months'",
    update: "UPDATE quantity_values SET maximum = 30 WHERE knowledge_node_id = 'n_qty_26_months'",
    whereUpdated: "knowledge_node_id = 'n_qty_26_months' AND maximum = 30",
    delete: [
      "DELETE FROM quantity_values WHERE knowledge_node_id = 'n_qty_26_months'",
      "DELETE FROM knowledge_nodes WHERE id = 'n_qty_26_months'",
    ],
  ),
  const CrudCase(
    'node_alternative_names',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO node_alternative_names VALUES ('n_grape_pinot_noir', 'Spätburgunder', 'spatburgunder', 'synonym')",
    ],
    where: "name_norm = 'spatburgunder'",
    update: "UPDATE node_alternative_names SET kind = 'spelling_variant' WHERE name_norm = 'spatburgunder'",
    whereUpdated: "name_norm = 'spatburgunder' AND kind = 'spelling_variant'",
    delete: [
      "DELETE FROM node_alternative_names WHERE name_norm = 'spatburgunder'",
    ],
  ),
  const CrudCase(
    'knowledge_relations',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO knowledge_relations VALUES ('n_grape_nebbiolo', 'HAS_BERRY_COLOUR', 'n_colour_black', '1900-01-01', NULL)",
    ],
    where: "subject_id = 'n_grape_nebbiolo' AND relation_type = 'HAS_BERRY_COLOUR'",
    update: "UPDATE knowledge_relations SET valid_until = '2030-01-01' WHERE subject_id = 'n_grape_nebbiolo' AND relation_type = 'HAS_BERRY_COLOUR'",
    whereUpdated:
        "subject_id = 'n_grape_nebbiolo' AND valid_until = '2030-01-01'",
    delete: [
      "DELETE FROM knowledge_relations WHERE subject_id = 'n_grape_nebbiolo' AND relation_type = 'HAS_BERRY_COLOUR'",
    ],
  ),
  const CrudCase(
    'knowledge_items',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO knowledge_items (id, subject_id, relation_type, object_id, domain_id, assertion_text, last_verified_at) VALUES ('ki_gevrey_grape', 'n_geo_gevrey', 'PERMITS_PRINCIPAL_GRAPE', 'n_grape_pinot_noir', 'geography', 'Pinot Noir is the principal grape of Gevrey-Chambertin.', $_ts)",
    ],
    where: "id = 'ki_gevrey_grape'",
    update: "UPDATE knowledge_items SET revision = 2, assertion_text = 'Reworded.' WHERE id = 'ki_gevrey_grape'",
    whereUpdated: "id = 'ki_gevrey_grape' AND revision = 2",
    delete: ["DELETE FROM knowledge_items WHERE id = 'ki_gevrey_grape'"],
  ),
  const CrudCase(
    'knowledge_item_prerequisites',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO knowledge_item_prerequisites VALUES ('ki_barolo_min_ageing', 'ki_chablis_grape')",
    ],
    where: "knowledge_item_id = 'ki_barolo_min_ageing'",
    update: "UPDATE knowledge_item_prerequisites SET prerequisite_item_id = 'ki_chablis_soil' WHERE knowledge_item_id = 'ki_barolo_min_ageing'",
    whereUpdated: "knowledge_item_id = 'ki_barolo_min_ageing' AND prerequisite_item_id = 'ki_chablis_soil'",
    delete: [
      "DELETE FROM knowledge_item_prerequisites WHERE knowledge_item_id = 'ki_barolo_min_ageing'",
    ],
  ),
  const CrudCase(
    'certification_knowledge_mappings',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO certification_knowledge_mappings VALUES ('WSET_L3', 'ki_barolo_min_ageing', 'secondary', 2, NULL)",
    ],
    where: "knowledge_item_id = 'ki_barolo_min_ageing'",
    update: "UPDATE certification_knowledge_mappings SET importance = 'tertiary' WHERE knowledge_item_id = 'ki_barolo_min_ageing'",
    whereUpdated: "knowledge_item_id = 'ki_barolo_min_ageing' AND importance = 'tertiary'",
    delete: [
      "DELETE FROM certification_knowledge_mappings WHERE knowledge_item_id = 'ki_barolo_min_ageing'",
    ],
  ),
  const CrudCase(
    'source_citations',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO source_citations (id, kind, title, publisher, accessed_on) VALUES ('src_crud', 'reference_work', 'A reference work', 'A publisher', '2026-09-24')",
    ],
    where: "id = 'src_crud'",
    update: "UPDATE source_citations SET title = 'A revised reference work' WHERE id = 'src_crud'",
    whereUpdated: "title = 'A revised reference work'",
    delete: ["DELETE FROM source_citations WHERE id = 'src_crud'"],
  ),
  const CrudCase(
    'knowledge_item_citations',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO knowledge_item_citations VALUES ('ki_chablis_soil', 'src_inao_chablis', NULL)",
    ],
    where: "knowledge_item_id = 'ki_chablis_soil'",
    update: "UPDATE knowledge_item_citations SET locator = 'Chapter 1' WHERE knowledge_item_id = 'ki_chablis_soil'",
    whereUpdated:
        "knowledge_item_id = 'ki_chablis_soil' AND locator = 'Chapter 1'",
    delete: [
      "DELETE FROM knowledge_item_citations WHERE knowledge_item_id = 'ki_chablis_soil'",
    ],
  ),
  const CrudCase(
    'question_templates',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO question_templates VALUES ('qt_ppg_rev_mcq', 'PERMITS_PRINCIPAL_GRAPE', 'reverse', 'mcq', 'en', 'Which appellation has {object.name} as its principal grape?', '', NULL)",
    ],
    where: "id = 'qt_ppg_rev_mcq'",
    update: "UPDATE question_templates SET prompt_template = 'Reworded: {object.name}?' WHERE id = 'qt_ppg_rev_mcq'",
    whereUpdated: "prompt_template = 'Reworded: {object.name}?'",
    delete: ["DELETE FROM question_templates WHERE id = 'qt_ppg_rev_mcq'"],
  ),
  const CrudCase(
    'tasting_grid_attributes',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO tasting_grid_attributes VALUES ('tg_wset_sat_l3', 'acidity', 'palate', 'Acidity', 3, 'single', 1)",
    ],
    where: "attribute_key = 'acidity'",
    update: "UPDATE tasting_grid_attributes SET label = 'Acidity level' WHERE attribute_key = 'acidity'",
    whereUpdated: "attribute_key = 'acidity' AND label = 'Acidity level'",
    delete: [
      "DELETE FROM tasting_grid_attributes WHERE attribute_key = 'acidity'",
    ],
  ),
  const CrudCase(
    'tasting_grid_values',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO tasting_grid_values VALUES ('tg_wset_sat_l3', 'primary_aromas', 'peach', 'peach', 3, NULL)",
    ],
    where: "value_key = 'peach'",
    update: "UPDATE tasting_grid_values SET label = 'white peach' WHERE value_key = 'peach'",
    whereUpdated: "value_key = 'peach' AND label = 'white peach'",
    delete: ["DELETE FROM tasting_grid_values WHERE value_key = 'peach'"],
  ),
  const CrudCase(
    'relation_set_assertions',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO relation_set_assertions VALUES ('n_geo_chablis', 'PERMITS_PRINCIPAL_GRAPE', 'forward', 'grape', '1938-01-13', NULL, 'src_inao_chablis', 'Article II')",
    ],
    where: "node_id = 'n_geo_chablis'",
    update: "UPDATE relation_set_assertions SET valid_until = '2030-01-01' WHERE node_id = 'n_geo_chablis'",
    whereUpdated: "node_id = 'n_geo_chablis' AND valid_until = '2030-01-01'",
    delete: [
      "DELETE FROM relation_set_assertions WHERE node_id = 'n_geo_chablis'",
    ],
  ),
  CrudCase(
    'map_layers',
    scope: Scope.curriculum,
    create: [_layer('ml_crud')],
    where: "id = 'ml_crud'",
    update: "UPDATE map_layers SET display_name = 'Renamed layer' WHERE id = 'ml_crud'",
    whereUpdated: "display_name = 'Renamed layer'",
    delete: ["DELETE FROM map_layers WHERE id = 'ml_crud'"],
  ),
  CrudCase(
    'map_layer_citations',
    scope: Scope.curriculum,
    create: [
      _layer('ml_cited'),
      "INSERT INTO map_layer_citations VALUES ('ml_cited', 'src_inao_chablis', 1)",
    ],
    where: "map_layer_id = 'ml_cited'",
    update: "UPDATE map_layer_citations SET position = 2 WHERE map_layer_id = 'ml_cited'",
    whereUpdated: "map_layer_id = 'ml_cited' AND position = 2",
    delete: [
      "DELETE FROM map_layer_citations WHERE map_layer_id = 'ml_cited'",
      "DELETE FROM map_layers WHERE id = 'ml_cited'",
    ],
  ),
  CrudCase(
    'node_geometries',
    scope: Scope.curriculum,
    create: [
      _layer('ml_drawn'),
      "INSERT INTO node_geometries VALUES ('n_geo_chablis', 'ml_drawn', 'n_geo_chablis', 3.6, 47.7, 4.0, 47.9, 3.8, 47.8)",
    ],
    where: "map_layer_id = 'ml_drawn'",
    update: "UPDATE node_geometries SET label_lon = 3.7 WHERE map_layer_id = 'ml_drawn'",
    whereUpdated: "map_layer_id = 'ml_drawn' AND label_lon = 3.7",
    delete: [
      "DELETE FROM node_geometries WHERE map_layer_id = 'ml_drawn'",
      "DELETE FROM map_layers WHERE id = 'ml_drawn'",
    ],
  ),
  // ---- Curriculum, generated -----------------------------------------------
  const CrudCase(
    'questions',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO question_templates VALUES ('qt_ageing_fwd_flashcard', 'MIN_AGEING', 'forward', 'flashcard', 'en', 'What is the minimum ageing of {subject.name}?', '', NULL)",
      "INSERT INTO questions VALUES ('ki_barolo_min_ageing', 'qt_ageing_fwd_flashcard', 'MIN_AGEING', 'What is the minimum ageing of Barolo?')",
    ],
    where: "knowledge_item_id = 'ki_barolo_min_ageing'",
    update: "UPDATE questions SET prompt_text = 'Reworded?' WHERE knowledge_item_id = 'ki_barolo_min_ageing'",
    whereUpdated: "knowledge_item_id = 'ki_barolo_min_ageing' AND prompt_text = 'Reworded?'",
    delete: [
      "DELETE FROM questions WHERE knowledge_item_id = 'ki_barolo_min_ageing'",
      "DELETE FROM question_templates WHERE id = 'qt_ageing_fwd_flashcard'",
    ],
  ),
  const CrudCase(
    'question_distractors',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO question_distractors VALUES ('ki_chablis_grape', 'qt_ppg_fwd_mcq', 'n_grape_nebbiolo', 2)",
    ],
    where: "knowledge_node_id = 'n_grape_nebbiolo'",
    update: "UPDATE question_distractors SET scope_rank = 3 WHERE knowledge_node_id = 'n_grape_nebbiolo'",
    whereUpdated: "knowledge_node_id = 'n_grape_nebbiolo' AND scope_rank = 3",
    delete: [
      "DELETE FROM question_distractors WHERE knowledge_node_id = 'n_grape_nebbiolo'",
    ],
  ),
  const CrudCase(
    'exercise_pools',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO exercise_pools VALUES (1, 'qt_ppg_fwd_mcq', 'n_geo_burgundy', 'Match each appellation with its principal grape.')",
    ],
    where: 'id = 1',
    update: "UPDATE exercise_pools SET prompt_text = 'Reworded.' WHERE id = 1",
    whereUpdated: "id = 1 AND prompt_text = 'Reworded.'",
    delete: ['DELETE FROM exercise_pools WHERE id = 1'],
  ),
  const CrudCase(
    'exercise_pool_items',
    scope: Scope.curriculum,
    create: [
      "INSERT INTO exercise_pools VALUES (2, 'qt_ppg_fwd_mcq', NULL, 'Order these.')",
      "INSERT INTO exercise_pool_items VALUES (2, 'ki_chablis_grape', NULL)",
    ],
    where: 'exercise_pool_id = 2',
    update:
        'UPDATE exercise_pool_items SET rank = 1 WHERE exercise_pool_id = 2',
    whereUpdated: 'exercise_pool_id = 2 AND rank = 1',
    delete: [
      'DELETE FROM exercise_pool_items WHERE exercise_pool_id = 2',
      'DELETE FROM exercise_pools WHERE id = 2',
    ],
  ),
  // ---- System -----------------------------------------------------------------
  const CrudCase(
    'curriculum_ingestions',
    scope: Scope.system,
    create: ['INSERT INTO curriculum_ingestions VALUES (1, $_ts)'],
    where: 'id = 1',
    update: "UPDATE curriculum_ingestions SET started_at = '2026-01-01T09:00:01.000Z' WHERE id = 1",
    whereUpdated: "started_at = '2026-01-01T09:00:01.000Z'",
    delete: ['DELETE FROM curriculum_ingestions WHERE id = 1'],
  ),
  // ---- User data ----------------------------------------------------------------
  const CrudCase(
    'user_profiles',
    scope: Scope.user,
    create: [
      "INSERT INTO user_profiles VALUES (1, 'WSET_L3', 15, 5, $_ts, $_ts)",
    ],
    where: 'id = 1',
    update: "UPDATE user_profiles SET active_certification_id = 'CMS_CERTIFIED', updated_at = '2026-01-02T09:00:00.000Z' WHERE id = 1",
    whereUpdated: "active_certification_id = 'CMS_CERTIFIED'",
    delete: ['DELETE FROM user_profiles WHERE id = 1'],
  ),
  CrudCase(
    'scheduler_configs',
    scope: Scope.user,
    create: [
      "INSERT INTO scheduler_configs VALUES (2, '$fsrsWeightsJson', 0.9, '[60, 600]', '[600]', 36500, 1, $_ts)",
    ],
    where: 'version = 2',
    update: 'UPDATE scheduler_configs SET desired_retention = 0.85 WHERE version = 2',
    whereUpdated: 'version = 2 AND desired_retention = 0.85',
    delete: ['DELETE FROM scheduler_configs WHERE version = 2'],
  ),
  const CrudCase(
    'review_states',
    scope: Scope.user,
    create: [
      "INSERT INTO review_states VALUES ('ki_chablis_soil', 1, 0, 2.3, 5.0, '2026-01-01T09:10:00.000Z', $_ts, 1, 0)",
    ],
    where: "knowledge_item_id = 'ki_chablis_soil'",
    update: "UPDATE review_states SET state = 2, step = NULL, stability = 3.1, due = '2026-01-04T09:10:00.000Z', last_review = '2026-01-01T09:10:00.000Z', reps = 2 WHERE knowledge_item_id = 'ki_chablis_soil'",
    whereUpdated: "knowledge_item_id = 'ki_chablis_soil' AND state = 2",
    delete: [
      "DELETE FROM review_states WHERE knowledge_item_id = 'ki_chablis_soil'",
    ],
  ),
  CrudCase(
    'review_events',
    scope: Scope.user,
    appendOnly: true,
    create: [_event(1)],
    where: 'id = ${_uuid(1)}',
    update: 'UPDATE review_events SET rating = 4 WHERE id = ${_uuid(1)}',
    whereUpdated: 'id = ${_uuid(1)}',
    delete: ['DELETE FROM review_events WHERE id = ${_uuid(1)}'],
  ),
  CrudCase(
    'review_event_options',
    scope: Scope.user,
    appendOnly: true,
    create: [
      _event(2),
      "INSERT INTO review_event_options VALUES (${_uuid(2)}, 1, 'n_grape_chardonnay')",
    ],
    where: 'review_event_id = ${_uuid(2)}',
    update:
        "UPDATE review_event_options SET knowledge_node_id = 'n_grape_pinot_noir' WHERE review_event_id = ${_uuid(2)}",
    whereUpdated: 'review_event_id = ${_uuid(2)}',
    delete: [
      'DELETE FROM review_event_options WHERE review_event_id = ${_uuid(2)}',
    ],
  ),
  CrudCase(
    'wine_journal_entries',
    scope: Scope.user,
    create: [_journal(10)],
    where: 'id = ${_uuid(10)}',
    update:
        "UPDATE wine_journal_entries SET rating = 4, updated_at = '2026-01-02T09:00:00.000Z' WHERE id = ${_uuid(10)}",
    whereUpdated: 'id = ${_uuid(10)} AND rating = 4',
    delete: ['DELETE FROM wine_journal_entries WHERE id = ${_uuid(10)}'],
  ),
  CrudCase(
    'wine_journal_entry_nodes',
    scope: Scope.user,
    create: [
      _journal(11),
      "INSERT INTO wine_journal_entry_nodes VALUES (${_uuid(11)}, 'n_geo_barolo')",
    ],
    where: 'wine_journal_entry_id = ${_uuid(11)}',
    update:
        "UPDATE wine_journal_entry_nodes SET knowledge_node_id = 'n_grape_nebbiolo' WHERE wine_journal_entry_id = ${_uuid(11)}",
    whereUpdated:
        "wine_journal_entry_id = ${_uuid(11)} AND knowledge_node_id = 'n_grape_nebbiolo'",
    delete: [
      'DELETE FROM wine_journal_entry_nodes WHERE wine_journal_entry_id = ${_uuid(11)}',
      'DELETE FROM wine_journal_entries WHERE id = ${_uuid(11)}',
    ],
  ),
  CrudCase(
    'tasting_sessions',
    scope: Scope.user,
    create: [_session(20)],
    where: 'id = ${_uuid(20)}',
    update:
        "UPDATE tasting_sessions SET completed_at = '2026-01-01T09:30:00.000Z', notes = 'Done' WHERE id = ${_uuid(20)}",
    whereUpdated: "id = ${_uuid(20)} AND notes = 'Done'",
    delete: ['DELETE FROM tasting_sessions WHERE id = ${_uuid(20)}'],
  ),
  CrudCase(
    'tasting_descriptors',
    scope: Scope.user,
    create: [
      _session(21),
      "INSERT INTO tasting_descriptors VALUES (${_uuid(21)}, 'tg_wset_sat_l3', 'sweetness', 'dry')",
    ],
    where: 'tasting_session_id = ${_uuid(21)}',
    update:
        "UPDATE tasting_descriptors SET value_key = 'off_dry' WHERE tasting_session_id = ${_uuid(21)}",
    whereUpdated: "tasting_session_id = ${_uuid(21)} AND value_key = 'off_dry'",
    delete: [
      'DELETE FROM tasting_descriptors WHERE tasting_session_id = ${_uuid(21)}',
      'DELETE FROM tasting_sessions WHERE id = ${_uuid(21)}',
    ],
  ),
];

void main() {
  late AppDatabase db;

  setUp(() async {
    db = openTestDatabase();
    await seedCurriculum(db);
    await seedSchedulerConfig(db);
  });
  tearDown(() => db.close());

  Future<int> count(String table, String where) async {
    final row = await db
        .customSelect('SELECT count(*) AS n FROM $table WHERE $where')
        .getSingle();
    return row.read<int>('n');
  }

  Future<void> inScope(Scope scope, Future<void> Function() body) =>
      scope == Scope.curriculum ? db.writeCurriculum(body) : body();

  test('every table in the schema has a CRUD case', () async {
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .map((row) => row.read<String>('name'))
        .get();
    expect(cases.map((c) => c.table).toSet(), tables.toSet());
    expect(tables, hasLength(37));
  });

  for (final c in cases) {
    test('CRUD: ${c.table}', () async {
      await inScope(c.scope, () => runSql(db, c.create));
      expect(await count(c.table, c.where), 1, reason: 'read after create');

      if (c.appendOnly) {
        await expectLater(
          db.customStatement(c.update),
          throwsA(isA<SqliteException>()),
        );
        await expectLater(
          runSql(db, c.delete),
          throwsA(isA<SqliteException>()),
        );
        expect(await count(c.table, c.where), 1, reason: 'row is immutable');
        return;
      }

      await inScope(c.scope, () => db.customStatement(c.update));
      expect(
        await count(c.table, c.whereUpdated),
        1,
        reason: 'read after update',
      );
      await inScope(c.scope, () => runSql(db, c.delete));
      expect(
        await count(c.table, c.whereUpdated),
        0,
        reason: 'read after delete',
      );
    });

    if (c.scope == Scope.curriculum) {
      test('guard: ${c.table} rejects writes outside the lock', () async {
        await expectLater(
          runSql(db, c.create),
          throwsA(isA<SqliteException>()),
        );
      });
    }
  }
}
