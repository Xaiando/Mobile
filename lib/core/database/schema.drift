-- =============================================================================
-- Sommelier Study App: canonical domain model, schema v1
--
-- Human-readable model and diagrams: docs/domain-model.md
-- Targets SQLite 3.53.4 (bundled on native and in sqlite3.wasm on Web).
-- This file is valid as plain SQLite DDL and as a Drift `.drift` file.
--
-- Conventions
--   * Tables are plural snake_case; the model names entities in singular
--     PascalCase (knowledge_relations <-> KnowledgeRelation).
--   * DATETIME columns hold UTC instants as ISO-8601 text with millisecond
--     precision, 'YYYY-MM-DDTHH:MM:SS.sssZ'. A CHECK enforces the exact form,
--     so text order equals time order on every platform.
--   * Date-only columns are TEXT 'YYYY-MM-DD', checked with date().
--   * BOOLEAN columns hold 0 or 1.
--   * Curriculum IDs are stable, opaque TEXT with a prefix per entity;
--     rows the user creates have UUID TEXT IDs.
--
-- Data classes (see docs/domain-model.md §2)
--   SYSTEM                 curriculum_ingestions
--   CURRICULUM, AUTHORED   shipped in the dataset; immutable at runtime
--   CURRICULUM, GENERATED  derived from authored rows; rebuilt on ingestion
--   USER                   created on the device; never touched by ingestion
-- =============================================================================


-- -----------------------------------------------------------------------------
-- SYSTEM
-- -----------------------------------------------------------------------------

-- A row exists only while a curriculum ingestion transaction is running.
-- Every curriculum table rejects writes when this table is empty (the
-- *_read_only_* triggers at the end of this file).
CREATE TABLE curriculum_ingestions (
  id          INTEGER  NOT NULL PRIMARY KEY CHECK (id = 1),
  started_at  DATETIME NOT NULL
    CHECK (strftime('%Y-%m-%dT%H:%M:%fZ', started_at) IS started_at)
);


-- -----------------------------------------------------------------------------
-- CURRICULUM, AUTHORED
-- -----------------------------------------------------------------------------

CREATE TABLE curriculum_releases (
  version       TEXT     NOT NULL PRIMARY KEY,
  checksum      TEXT     NOT NULL,
  published_at  DATETIME NOT NULL
    CHECK (strftime('%Y-%m-%dT%H:%M:%fZ', published_at) IS published_at),
  ingested_at   DATETIME NOT NULL
    CHECK (strftime('%Y-%m-%dT%H:%M:%fZ', ingested_at) IS ingested_at)
);

CREATE TABLE curriculum_domains (
  id            TEXT    NOT NULL PRIMARY KEY
    CHECK (id NOT GLOB '*[^a-z_]*'),
  display_name  TEXT    NOT NULL,
  position      INTEGER NOT NULL UNIQUE
);

CREATE TABLE tasting_grids (
  id            TEXT NOT NULL PRIMARY KEY
    CHECK (id GLOB 'tg_?*' AND id NOT GLOB '*[^a-z0-9_]*'),
  framework     TEXT NOT NULL CHECK (framework IN ('WSET_SAT', 'CMS_DTM')),
  version       TEXT NOT NULL,
  display_name  TEXT NOT NULL,
  UNIQUE (framework, version)
);

CREATE TABLE certifications (
  id                         TEXT    NOT NULL PRIMARY KEY
    CHECK (id NOT GLOB '*[^A-Z0-9_]*'),
  organization               TEXT    NOT NULL CHECK (organization IN ('WSET', 'CMS')),
  level                      INTEGER NOT NULL CHECK (level >= 1),
  display_name               TEXT    NOT NULL,
  includes_certification_id  TEXT    REFERENCES certifications (id),
  default_tasting_grid_id    TEXT    REFERENCES tasting_grids (id),
  is_selectable              BOOLEAN NOT NULL DEFAULT 0 CHECK (is_selectable IN (0, 1)),
  UNIQUE (organization, level),
  CHECK (includes_certification_id IS NOT id)
);

CREATE TABLE node_types (
  id     TEXT NOT NULL PRIMARY KEY CHECK (id NOT GLOB '*[^a-z_]*'),
  label  TEXT NOT NULL
);

CREATE TABLE relation_types (
  id                              TEXT    NOT NULL PRIMARY KEY
    CHECK (id NOT GLOB '*[^A-Z_]*'),
  label                           TEXT    NOT NULL,
  reverse_label                   TEXT    NOT NULL,
  cardinality                     TEXT    NOT NULL CHECK (cardinality IN ('one', 'many')),
  is_transitive                   BOOLEAN NOT NULL DEFAULT 0 CHECK (is_transitive IN (0, 1)),
  is_reverse_safe                 BOOLEAN NOT NULL DEFAULT 0 CHECK (is_reverse_safe IN (0, 1)),
  default_domain_id               TEXT    NOT NULL REFERENCES curriculum_domains (id),
  distractor_match_relation_type  TEXT    REFERENCES relation_types (id)
);

CREATE TABLE relation_type_signatures (
  relation_type      TEXT NOT NULL REFERENCES relation_types (id),
  subject_node_type  TEXT NOT NULL REFERENCES node_types (id),
  object_node_type   TEXT NOT NULL REFERENCES node_types (id),
  PRIMARY KEY (relation_type, subject_node_type, object_node_type)
);

-- name_norm is the matching key (lower case, diacritics and appellation
-- suffixes removed). It is computed in Dart during ingestion because SQLite
-- folds case for ASCII only.
CREATE TABLE knowledge_nodes (
  id           TEXT NOT NULL PRIMARY KEY
    CHECK (id GLOB 'n_?*' AND id NOT GLOB '*[^a-z0-9_]*'),
  node_type    TEXT NOT NULL REFERENCES node_types (id),
  name         TEXT NOT NULL,
  name_norm    TEXT NOT NULL CHECK (name_norm NOT GLOB '*[A-Z]*'),
  valid_from   TEXT CHECK (valid_from IS NULL OR date(valid_from) IS valid_from),
  valid_until  TEXT CHECK (valid_until IS NULL OR date(valid_until) IS valid_until),
  UNIQUE (node_type, name_norm),
  UNIQUE (id, node_type),
  CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until > valid_from)
);
CREATE INDEX knowledge_nodes_by_name_norm ON knowledge_nodes (name_norm);

-- Subtype of KnowledgeNode for literal facts (minimum ageing, yields, service
-- temperatures). The composite FK only accepts nodes of type 'quantity'.
CREATE TABLE quantity_values (
  knowledge_node_id  TEXT NOT NULL PRIMARY KEY,
  node_type          TEXT NOT NULL DEFAULT 'quantity' CHECK (node_type = 'quantity'),
  minimum            REAL NOT NULL,
  maximum            REAL,
  unit               TEXT NOT NULL,
  FOREIGN KEY (knowledge_node_id, node_type) REFERENCES knowledge_nodes (id, node_type),
  CHECK (maximum IS NULL OR maximum >= minimum)
);

-- Grape synonyms (Shiraz/Syrah), former names of renamed appellations,
-- abbreviations and spelling variants, for matching journal text.
CREATE TABLE node_alternative_names (
  knowledge_node_id  TEXT NOT NULL REFERENCES knowledge_nodes (id),
  name               TEXT NOT NULL,
  name_norm          TEXT NOT NULL CHECK (name_norm NOT GLOB '*[A-Z]*'),
  kind               TEXT NOT NULL CHECK (kind IN (
                       'synonym', 'former_name', 'abbreviation', 'spelling_variant')),
  PRIMARY KEY (knowledge_node_id, name_norm)
);
CREATE INDEX node_alternative_names_by_norm ON node_alternative_names (name_norm);

-- The graph edge. Legal validity lives here, so an expired fact stops
-- affecting traversal, distractors and answer sets.
CREATE TABLE knowledge_relations (
  subject_id     TEXT NOT NULL REFERENCES knowledge_nodes (id),
  relation_type  TEXT NOT NULL REFERENCES relation_types (id),
  object_id      TEXT NOT NULL REFERENCES knowledge_nodes (id),
  valid_from     TEXT NOT NULL CHECK (date(valid_from) IS valid_from),
  valid_until    TEXT CHECK (valid_until IS NULL OR date(valid_until) IS valid_until),
  PRIMARY KEY (subject_id, relation_type, object_id),
  CHECK (subject_id <> object_id),
  CHECK (valid_until IS NULL OR valid_until > valid_from)
);
CREATE INDEX knowledge_relations_by_object ON knowledge_relations (object_id, relation_type);

-- The atomic unit of study: the testable assertion of exactly one relation.
CREATE TABLE knowledge_items (
  id                     TEXT     NOT NULL PRIMARY KEY
    CHECK (id GLOB 'ki_?*' AND id NOT GLOB '*[^a-z0-9_]*'),
  subject_id             TEXT     NOT NULL,
  relation_type          TEXT     NOT NULL,
  object_id              TEXT     NOT NULL,
  domain_id              TEXT     NOT NULL REFERENCES curriculum_domains (id),
  assertion_text         TEXT     NOT NULL,
  revision               INTEGER  NOT NULL DEFAULT 1 CHECK (revision >= 1),
  last_verified_at       DATETIME NOT NULL
    CHECK (strftime('%Y-%m-%dT%H:%M:%fZ', last_verified_at) IS last_verified_at),
  verification_status    TEXT     NOT NULL DEFAULT 'unverified'
    CHECK (verification_status IN ('unverified', 'verified')),
  superseded_by_item_id  TEXT     REFERENCES knowledge_items (id),
  is_distinctive         BOOLEAN  NOT NULL DEFAULT 0 CHECK (is_distinctive IN (0, 1)),
  mcq_disabled           BOOLEAN  NOT NULL DEFAULT 0 CHECK (mcq_disabled IN (0, 1)),
  UNIQUE (subject_id, relation_type, object_id),
  UNIQUE (id, relation_type),
  FOREIGN KEY (subject_id, relation_type, object_id)
    REFERENCES knowledge_relations (subject_id, relation_type, object_id),
  CHECK (superseded_by_item_id IS NOT id)
);
CREATE INDEX knowledge_items_by_object ON knowledge_items (object_id);
CREATE INDEX knowledge_items_by_domain ON knowledge_items (domain_id);

CREATE TABLE knowledge_item_prerequisites (
  knowledge_item_id     TEXT NOT NULL REFERENCES knowledge_items (id),
  prerequisite_item_id  TEXT NOT NULL REFERENCES knowledge_items (id),
  PRIMARY KEY (knowledge_item_id, prerequisite_item_id),
  CHECK (knowledge_item_id <> prerequisite_item_id)
);
CREATE INDEX knowledge_item_prerequisites_by_prerequisite
  ON knowledge_item_prerequisites (prerequisite_item_id);

CREATE TABLE certification_knowledge_mappings (
  certification_id   TEXT    NOT NULL REFERENCES certifications (id),
  knowledge_item_id  TEXT    NOT NULL REFERENCES knowledge_items (id),
  importance         TEXT    NOT NULL CHECK (importance IN ('core', 'secondary', 'tertiary')),
  minimum_depth      INTEGER NOT NULL CHECK (minimum_depth BETWEEN 1 AND 5),
  syllabus_ref       TEXT,
  PRIMARY KEY (certification_id, knowledge_item_id)
);
CREATE INDEX certification_knowledge_mappings_by_item
  ON certification_knowledge_mappings (knowledge_item_id);

CREATE TABLE source_citations (
  id                   TEXT NOT NULL PRIMARY KEY
    CHECK (id GLOB 'src_?*' AND id NOT GLOB '*[^a-z0-9_]*'),
  kind                 TEXT NOT NULL CHECK (kind IN (
                         'legislation', 'regulator_register', 'government_publication',
                         'academic', 'reference_work', 'dataset')),
  title                TEXT NOT NULL,
  publisher            TEXT NOT NULL,
  jurisdiction         TEXT,
  document_identifier  TEXT,
  url                  TEXT UNIQUE,
  published_on         TEXT CHECK (published_on IS NULL OR date(published_on) IS published_on),
  accessed_on          TEXT NOT NULL CHECK (date(accessed_on) IS accessed_on),
  license              TEXT,
  attribution_text     TEXT
);

CREATE TABLE knowledge_item_citations (
  knowledge_item_id   TEXT NOT NULL REFERENCES knowledge_items (id),
  source_citation_id  TEXT NOT NULL REFERENCES source_citations (id),
  locator             TEXT,
  PRIMARY KEY (knowledge_item_id, source_citation_id)
);
CREATE INDEX knowledge_item_citations_by_source ON knowledge_item_citations (source_citation_id);

CREATE TABLE question_templates (
  id               TEXT NOT NULL PRIMARY KEY
    CHECK (id GLOB 'qt_?*' AND id NOT GLOB '*[^a-z0-9_]*'),
  relation_type    TEXT NOT NULL REFERENCES relation_types (id),
  direction        TEXT NOT NULL CHECK (direction IN ('forward', 'reverse')),
  mode             TEXT NOT NULL CHECK (mode IN ('flashcard', 'mcq')),
  locale           TEXT NOT NULL DEFAULT 'en',
  prompt_template  TEXT NOT NULL,
  UNIQUE (relation_type, direction, mode, locale),
  UNIQUE (id, relation_type)
);

CREATE TABLE tasting_grid_attributes (
  tasting_grid_id  TEXT    NOT NULL REFERENCES tasting_grids (id),
  attribute_key    TEXT    NOT NULL CHECK (attribute_key NOT GLOB '*[^a-z0-9_]*'),
  section          TEXT    NOT NULL,
  label            TEXT    NOT NULL,
  position         INTEGER NOT NULL,
  selection        TEXT    NOT NULL CHECK (selection IN ('single', 'multi')),
  is_required      BOOLEAN NOT NULL DEFAULT 1 CHECK (is_required IN (0, 1)),
  PRIMARY KEY (tasting_grid_id, attribute_key),
  UNIQUE (tasting_grid_id, position)
);

CREATE TABLE tasting_grid_values (
  tasting_grid_id    TEXT    NOT NULL,
  attribute_key      TEXT    NOT NULL,
  value_key          TEXT    NOT NULL CHECK (value_key NOT GLOB '*[^a-z0-9_]*'),
  label              TEXT    NOT NULL,
  position           INTEGER NOT NULL,
  knowledge_node_id  TEXT    REFERENCES knowledge_nodes (id),
  PRIMARY KEY (tasting_grid_id, attribute_key, value_key),
  UNIQUE (tasting_grid_id, attribute_key, position),
  FOREIGN KEY (tasting_grid_id, attribute_key)
    REFERENCES tasting_grid_attributes (tasting_grid_id, attribute_key)
);


-- -----------------------------------------------------------------------------
-- CURRICULUM, GENERATED (rebuilt in full by every ingestion; no user table
-- references these, so they can be regenerated freely)
-- -----------------------------------------------------------------------------

-- A servable question: one template applied to one item. The composite FKs
-- guarantee the template belongs to the item's relation type.
CREATE TABLE questions (
  knowledge_item_id     TEXT NOT NULL,
  question_template_id  TEXT NOT NULL,
  relation_type         TEXT NOT NULL,
  prompt_text           TEXT NOT NULL,
  PRIMARY KEY (knowledge_item_id, question_template_id),
  FOREIGN KEY (knowledge_item_id, relation_type)
    REFERENCES knowledge_items (id, relation_type),
  FOREIGN KEY (question_template_id, relation_type)
    REFERENCES question_templates (id, relation_type)
);

-- The pool of valid wrong answers for an MCQ question; 3 are drawn per
-- presentation. scope_rank 0 = nearest geographic scope.
CREATE TABLE question_distractors (
  knowledge_item_id     TEXT    NOT NULL,
  question_template_id  TEXT    NOT NULL,
  knowledge_node_id     TEXT    NOT NULL REFERENCES knowledge_nodes (id),
  scope_rank            INTEGER NOT NULL CHECK (scope_rank >= 0),
  PRIMARY KEY (knowledge_item_id, question_template_id, knowledge_node_id),
  FOREIGN KEY (knowledge_item_id, question_template_id)
    REFERENCES questions (knowledge_item_id, question_template_id) ON DELETE CASCADE
);


-- -----------------------------------------------------------------------------
-- USER (mutable; created on the device; never touched by ingestion)
-- -----------------------------------------------------------------------------

CREATE TABLE user_profiles (
  id                       INTEGER  NOT NULL PRIMARY KEY CHECK (id = 1),
  active_certification_id  TEXT     NOT NULL REFERENCES certifications (id),
  session_size             INTEGER  NOT NULL DEFAULT 15 CHECK (session_size BETWEEN 1 AND 100),
  new_items_per_session    INTEGER  NOT NULL DEFAULT 5 CHECK (new_items_per_session >= 0),
  created_at               DATETIME NOT NULL
    CHECK (strftime('%Y-%m-%dT%H:%M:%fZ', created_at) IS created_at),
  updated_at               DATETIME NOT NULL
    CHECK (strftime('%Y-%m-%dT%H:%M:%fZ', updated_at) IS updated_at),
  CHECK (new_items_per_session <= session_size),
  CHECK (unixepoch(updated_at, 'subsec') >= unixepoch(created_at, 'subsec'))
);

CREATE TABLE scheduler_configs (
  version                   INTEGER  NOT NULL PRIMARY KEY CHECK (version >= 1),
  weights                   TEXT     NOT NULL CHECK (json_valid(weights)
                              AND json_type(weights) = 'array'
                              AND json_array_length(weights) = 21),
  desired_retention         REAL     NOT NULL CHECK (desired_retention > 0 AND desired_retention < 1),
  learning_steps_seconds    TEXT     NOT NULL CHECK (json_valid(learning_steps_seconds)
                              AND json_type(learning_steps_seconds) = 'array'),
  relearning_steps_seconds  TEXT     NOT NULL CHECK (json_valid(relearning_steps_seconds)
                              AND json_type(relearning_steps_seconds) = 'array'),
  maximum_interval_days     INTEGER  NOT NULL CHECK (maximum_interval_days >= 1),
  enable_fuzzing            BOOLEAN  NOT NULL CHECK (enable_fuzzing IN (0, 1)),
  created_at                DATETIME NOT NULL
    CHECK (strftime('%Y-%m-%dT%H:%M:%fZ', created_at) IS created_at)
);

-- Projection of review_events: the latest event's after-state plus counts.
-- Rebuildable from the log; written in the same transaction as each event.
CREATE TABLE review_states (
  knowledge_item_id  TEXT     NOT NULL PRIMARY KEY REFERENCES knowledge_items (id),
  state              INTEGER  NOT NULL CHECK (state BETWEEN 1 AND 3),
  step               INTEGER  CHECK (step IS NULL OR step >= 0),
  stability          REAL     NOT NULL CHECK (stability > 0),
  difficulty         REAL     NOT NULL CHECK (difficulty BETWEEN 1 AND 10),
  due                DATETIME NOT NULL
    CHECK (strftime('%Y-%m-%dT%H:%M:%fZ', due) IS due),
  last_review        DATETIME NOT NULL
    CHECK (strftime('%Y-%m-%dT%H:%M:%fZ', last_review) IS last_review),
  reps               INTEGER  NOT NULL CHECK (reps >= 1),
  lapses             INTEGER  NOT NULL DEFAULT 0 CHECK (lapses >= 0),
  CHECK ((state = 2) = (step IS NULL)),
  CHECK (lapses < reps),
  CHECK (unixepoch(due, 'subsec') > unixepoch(last_review, 'subsec'))
);
CREATE INDEX review_states_by_due ON review_states (due);

CREATE TABLE review_events (
  id                        TEXT     NOT NULL PRIMARY KEY
    CHECK (length(id) = 36 AND id NOT GLOB '*[^0-9a-f-]*'),
  knowledge_item_id         TEXT     NOT NULL REFERENCES knowledge_items (id),
  question_template_id      TEXT     NOT NULL REFERENCES question_templates (id),
  reviewed_at               DATETIME NOT NULL
    CHECK (strftime('%Y-%m-%dT%H:%M:%fZ', reviewed_at) IS reviewed_at),
  rating                    INTEGER  NOT NULL CHECK (rating BETWEEN 1 AND 4),
  response_ms               INTEGER  CHECK (response_ms IS NULL OR response_ms >= 0),
  seed                      INTEGER,
  selected_node_id          TEXT     REFERENCES knowledge_nodes (id),
  scheduler_config_version  INTEGER  NOT NULL REFERENCES scheduler_configs (version),
  state_after               INTEGER  NOT NULL CHECK (state_after BETWEEN 1 AND 3),
  step_after                INTEGER  CHECK (step_after IS NULL OR step_after >= 0),
  stability_after           REAL     NOT NULL CHECK (stability_after > 0),
  difficulty_after          REAL     NOT NULL CHECK (difficulty_after BETWEEN 1 AND 10),
  due_after                 DATETIME NOT NULL
    CHECK (strftime('%Y-%m-%dT%H:%M:%fZ', due_after) IS due_after),
  CHECK ((state_after = 2) = (step_after IS NULL)),
  CHECK (unixepoch(due_after, 'subsec') > unixepoch(reviewed_at, 'subsec'))
);
CREATE INDEX review_events_by_item ON review_events (knowledge_item_id, reviewed_at);
CREATE INDEX review_events_by_time ON review_events (reviewed_at);

-- The options shown for an MCQ presentation, in display order.
CREATE TABLE review_event_options (
  review_event_id    TEXT    NOT NULL REFERENCES review_events (id),
  position           INTEGER NOT NULL CHECK (position BETWEEN 1 AND 4),
  knowledge_node_id  TEXT    NOT NULL REFERENCES knowledge_nodes (id),
  PRIMARY KEY (review_event_id, position),
  UNIQUE (review_event_id, knowledge_node_id)
);

CREATE TRIGGER review_events_append_only_update BEFORE UPDATE ON review_events
BEGIN SELECT RAISE(ABORT, 'review_events is append-only'); END;
CREATE TRIGGER review_events_append_only_delete BEFORE DELETE ON review_events
BEGIN SELECT RAISE(ABORT, 'review_events is append-only'); END;
CREATE TRIGGER review_event_options_append_only_update BEFORE UPDATE ON review_event_options
BEGIN SELECT RAISE(ABORT, 'review_event_options is append-only'); END;
CREATE TRIGGER review_event_options_append_only_delete BEFORE DELETE ON review_event_options
BEGIN SELECT RAISE(ABORT, 'review_event_options is append-only'); END;

CREATE TABLE wine_journal_entries (
  id                TEXT     NOT NULL PRIMARY KEY
    CHECK (length(id) = 36 AND id NOT GLOB '*[^0-9a-f-]*'),
  tasted_on         TEXT     CHECK (tasted_on IS NULL OR date(tasted_on) IS tasted_on),
  producer_name     TEXT,
  cuvee_name        TEXT,
  vintage           INTEGER  CHECK (vintage IS NULL OR vintage BETWEEN 1800 AND 2100),
  is_non_vintage    BOOLEAN  NOT NULL DEFAULT 0 CHECK (is_non_vintage IN (0, 1)),
  appellation_text  TEXT,
  grapes_text       TEXT,
  abv_percent       REAL     CHECK (abv_percent IS NULL OR (abv_percent > 0 AND abv_percent < 100)),
  rating            INTEGER  CHECK (rating IS NULL OR rating BETWEEN 1 AND 5),
  tasting_notes     TEXT,
  photo_ref         TEXT,
  created_at        DATETIME NOT NULL
    CHECK (strftime('%Y-%m-%dT%H:%M:%fZ', created_at) IS created_at),
  updated_at        DATETIME NOT NULL
    CHECK (strftime('%Y-%m-%dT%H:%M:%fZ', updated_at) IS updated_at),
  CHECK (NOT (is_non_vintage = 1 AND vintage IS NOT NULL)),
  CHECK (unixepoch(updated_at, 'subsec') >= unixepoch(created_at, 'subsec'))
);
CREATE INDEX wine_journal_entries_by_tasted_on ON wine_journal_entries (tasted_on);

CREATE TABLE wine_journal_entry_nodes (
  wine_journal_entry_id  TEXT NOT NULL REFERENCES wine_journal_entries (id) ON DELETE CASCADE,
  knowledge_node_id      TEXT NOT NULL REFERENCES knowledge_nodes (id),
  PRIMARY KEY (wine_journal_entry_id, knowledge_node_id)
);
CREATE INDEX wine_journal_entry_nodes_by_node ON wine_journal_entry_nodes (knowledge_node_id);

CREATE TABLE tasting_sessions (
  id                     TEXT     NOT NULL PRIMARY KEY
    CHECK (length(id) = 36 AND id NOT GLOB '*[^0-9a-f-]*'),
  tasting_grid_id        TEXT     NOT NULL REFERENCES tasting_grids (id),
  wine_journal_entry_id  TEXT     REFERENCES wine_journal_entries (id) ON DELETE SET NULL,
  is_blind               BOOLEAN  NOT NULL DEFAULT 1 CHECK (is_blind IN (0, 1)),
  started_at             DATETIME NOT NULL
    CHECK (strftime('%Y-%m-%dT%H:%M:%fZ', started_at) IS started_at),
  completed_at           DATETIME
    CHECK (completed_at IS NULL OR strftime('%Y-%m-%dT%H:%M:%fZ', completed_at) IS completed_at),
  notes                  TEXT,
  UNIQUE (id, tasting_grid_id),
  CHECK (completed_at IS NULL
         OR unixepoch(completed_at, 'subsec') >= unixepoch(started_at, 'subsec'))
);
CREATE INDEX tasting_sessions_by_started_at ON tasting_sessions (started_at);
CREATE INDEX tasting_sessions_by_journal_entry ON tasting_sessions (wine_journal_entry_id);

-- One observation. The composite FKs restrict values to the session's own
-- grid, so a SAT session cannot store DTM terms (TASK-008).
CREATE TABLE tasting_descriptors (
  tasting_session_id  TEXT NOT NULL,
  tasting_grid_id     TEXT NOT NULL,
  attribute_key       TEXT NOT NULL,
  value_key           TEXT NOT NULL,
  PRIMARY KEY (tasting_session_id, attribute_key, value_key),
  FOREIGN KEY (tasting_session_id, tasting_grid_id)
    REFERENCES tasting_sessions (id, tasting_grid_id) ON DELETE CASCADE,
  FOREIGN KEY (tasting_grid_id, attribute_key, value_key)
    REFERENCES tasting_grid_values (tasting_grid_id, attribute_key, value_key)
);

-- A 'single' attribute (e.g. acidity) accepts one value per session.
CREATE TRIGGER tasting_descriptors_single_selection BEFORE INSERT ON tasting_descriptors
WHEN (SELECT selection FROM tasting_grid_attributes
       WHERE tasting_grid_id = NEW.tasting_grid_id AND attribute_key = NEW.attribute_key) = 'single'
  AND EXISTS (SELECT 1 FROM tasting_descriptors
               WHERE tasting_session_id = NEW.tasting_session_id
                 AND attribute_key = NEW.attribute_key)
BEGIN SELECT RAISE(ABORT, 'attribute accepts a single value'); END;


-- -----------------------------------------------------------------------------
-- CURRICULUM GUARDS (generated by the same rule for every curriculum table)
-- Curriculum tables are read-only unless a curriculum_ingestions row exists,
-- i.e. only inside the ingestion transaction.
-- -----------------------------------------------------------------------------
CREATE TRIGGER curriculum_releases_read_only_insert BEFORE INSERT ON curriculum_releases
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER curriculum_releases_read_only_update BEFORE UPDATE ON curriculum_releases
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER curriculum_releases_read_only_delete BEFORE DELETE ON curriculum_releases
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER curriculum_domains_read_only_insert BEFORE INSERT ON curriculum_domains
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER curriculum_domains_read_only_update BEFORE UPDATE ON curriculum_domains
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER curriculum_domains_read_only_delete BEFORE DELETE ON curriculum_domains
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER tasting_grids_read_only_insert BEFORE INSERT ON tasting_grids
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER tasting_grids_read_only_update BEFORE UPDATE ON tasting_grids
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER tasting_grids_read_only_delete BEFORE DELETE ON tasting_grids
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER certifications_read_only_insert BEFORE INSERT ON certifications
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER certifications_read_only_update BEFORE UPDATE ON certifications
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER certifications_read_only_delete BEFORE DELETE ON certifications
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER node_types_read_only_insert BEFORE INSERT ON node_types
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER node_types_read_only_update BEFORE UPDATE ON node_types
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER node_types_read_only_delete BEFORE DELETE ON node_types
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER relation_types_read_only_insert BEFORE INSERT ON relation_types
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER relation_types_read_only_update BEFORE UPDATE ON relation_types
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER relation_types_read_only_delete BEFORE DELETE ON relation_types
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER relation_type_signatures_read_only_insert BEFORE INSERT ON relation_type_signatures
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER relation_type_signatures_read_only_update BEFORE UPDATE ON relation_type_signatures
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER relation_type_signatures_read_only_delete BEFORE DELETE ON relation_type_signatures
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER knowledge_nodes_read_only_insert BEFORE INSERT ON knowledge_nodes
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER knowledge_nodes_read_only_update BEFORE UPDATE ON knowledge_nodes
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER knowledge_nodes_read_only_delete BEFORE DELETE ON knowledge_nodes
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER quantity_values_read_only_insert BEFORE INSERT ON quantity_values
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER quantity_values_read_only_update BEFORE UPDATE ON quantity_values
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER quantity_values_read_only_delete BEFORE DELETE ON quantity_values
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER node_alternative_names_read_only_insert BEFORE INSERT ON node_alternative_names
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER node_alternative_names_read_only_update BEFORE UPDATE ON node_alternative_names
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER node_alternative_names_read_only_delete BEFORE DELETE ON node_alternative_names
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER knowledge_relations_read_only_insert BEFORE INSERT ON knowledge_relations
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER knowledge_relations_read_only_update BEFORE UPDATE ON knowledge_relations
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER knowledge_relations_read_only_delete BEFORE DELETE ON knowledge_relations
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER knowledge_items_read_only_insert BEFORE INSERT ON knowledge_items
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER knowledge_items_read_only_update BEFORE UPDATE ON knowledge_items
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER knowledge_items_read_only_delete BEFORE DELETE ON knowledge_items
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER knowledge_item_prerequisites_read_only_insert BEFORE INSERT ON knowledge_item_prerequisites
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER knowledge_item_prerequisites_read_only_update BEFORE UPDATE ON knowledge_item_prerequisites
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER knowledge_item_prerequisites_read_only_delete BEFORE DELETE ON knowledge_item_prerequisites
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER certification_knowledge_mappings_read_only_insert BEFORE INSERT ON certification_knowledge_mappings
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER certification_knowledge_mappings_read_only_update BEFORE UPDATE ON certification_knowledge_mappings
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER certification_knowledge_mappings_read_only_delete BEFORE DELETE ON certification_knowledge_mappings
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER source_citations_read_only_insert BEFORE INSERT ON source_citations
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER source_citations_read_only_update BEFORE UPDATE ON source_citations
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER source_citations_read_only_delete BEFORE DELETE ON source_citations
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER knowledge_item_citations_read_only_insert BEFORE INSERT ON knowledge_item_citations
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER knowledge_item_citations_read_only_update BEFORE UPDATE ON knowledge_item_citations
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER knowledge_item_citations_read_only_delete BEFORE DELETE ON knowledge_item_citations
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER question_templates_read_only_insert BEFORE INSERT ON question_templates
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER question_templates_read_only_update BEFORE UPDATE ON question_templates
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER question_templates_read_only_delete BEFORE DELETE ON question_templates
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER tasting_grid_attributes_read_only_insert BEFORE INSERT ON tasting_grid_attributes
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER tasting_grid_attributes_read_only_update BEFORE UPDATE ON tasting_grid_attributes
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER tasting_grid_attributes_read_only_delete BEFORE DELETE ON tasting_grid_attributes
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER tasting_grid_values_read_only_insert BEFORE INSERT ON tasting_grid_values
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER tasting_grid_values_read_only_update BEFORE UPDATE ON tasting_grid_values
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER tasting_grid_values_read_only_delete BEFORE DELETE ON tasting_grid_values
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER questions_read_only_insert BEFORE INSERT ON questions
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER questions_read_only_update BEFORE UPDATE ON questions
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER questions_read_only_delete BEFORE DELETE ON questions
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER question_distractors_read_only_insert BEFORE INSERT ON question_distractors
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER question_distractors_read_only_update BEFORE UPDATE ON question_distractors
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
CREATE TRIGGER question_distractors_read_only_delete BEFORE DELETE ON question_distractors
WHEN NOT EXISTS (SELECT 1 FROM curriculum_ingestions)
BEGIN SELECT RAISE(ABORT, 'curriculum is read-only outside ingestion'); END;
