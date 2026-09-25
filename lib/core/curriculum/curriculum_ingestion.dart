import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../database/curriculum_writes.dart';
import '../questions/question_generator.dart';
import '../time/utc_clock.dart';
import 'curriculum_dataset.dart';
import 'curriculum_validator.dart';

/// Thrown when a dataset cannot be ingested. Nothing is written.
class CurriculumIngestionException implements Exception {
  CurriculumIngestionException(this.message);

  final String message;

  @override
  String toString() => 'Curriculum ingestion failed: $message';
}

/// What [CurriculumIngester.ensureCurrent] did.
enum IngestionOutcome {
  /// First launch: the database had no curriculum.
  installed,

  /// The bundled release is newer than the installed one.
  upgraded,

  /// Same version, different content: re-ingested to match the bundle.
  refreshed,

  /// The bundled release is already installed.
  upToDate,

  /// The installed release is newer than the bundle (an app downgrade); it is
  /// kept, because ingestion never removes authored rows.
  newerInstalled,
}

/// Loads the bundled curriculum into the database (architecture audit V-7).
///
/// A release is validated first, then written in one transaction under the
/// curriculum write lock: authored rows are upserted and never deleted, the
/// generated tables are rebuilt, and user tables are not touched.
class CurriculumIngester {
  CurriculumIngester(this.db, {Clock? clock}) : _clock = clock ?? const Clock();

  final AppDatabase db;
  final Clock _clock;

  /// Brings the database up to the bundled [dataset].
  Future<IngestionOutcome> ensureCurrent(CurriculumDataset dataset) async {
    final installed = await installedRelease();
    if (installed == null) {
      await ingest(dataset);
      return IngestionOutcome.installed;
    }
    final order = compareVersions(dataset.version, installed.version);
    if (order < 0) return IngestionOutcome.newerInstalled;
    if (order == 0 && installed.checksum == dataset.checksum) {
      return IngestionOutcome.upToDate;
    }
    await ingest(dataset);
    return order > 0 ? IngestionOutcome.upgraded : IngestionOutcome.refreshed;
  }

  /// The newest installed release, or `null` before the first ingestion.
  Future<CurriculumRelease?> installedRelease() async {
    final releases = await db.select(db.curriculumReleases).get();
    if (releases.isEmpty) return null;
    releases.sort((a, b) => compareVersions(a.version, b.version));
    return releases.last;
  }

  /// Validates [dataset] and writes it in a single transaction, then
  /// regenerates the questions from it. Returns the generation report.
  Future<GenerationReport> ingest(CurriculumDataset dataset) async {
    final report = validateDataset(dataset);
    if (!report.isValid) {
      throw CurriculumIngestionException(
        'release ${dataset.version} fails validation:\n'
        '${report.errors.join('\n')}',
      );
    }
    return db.writeCurriculum(() async {
      // Rows may reference rows later in the same release (a track's
      // included track, a superseding item), so check keys at commit.
      await db.customStatement('PRAGMA defer_foreign_keys = ON');
      await _refuseRemovals(dataset);
      await _upsertAuthored(dataset);
      // Generated tables are derived from the authored rows and nothing
      // references them, so they are rebuilt wholesale (domain model §2).
      // Composite formats will generate their pools (task F3); until then
      // there are none.
      await db.delete(db.exercisePoolItems).go();
      await db.delete(db.exercisePools).go();
      final generated = await QuestionGenerator(
        db,
        today: localToday(_clock),
      ).generate();
      await db
          .into(db.curriculumReleases)
          .insertOnConflictUpdate(
            CurriculumRelease(
              version: dataset.version,
              checksum: dataset.checksum,
              publishedAt: dataset.publishedAt,
              ingestedAt: utcNow(_clock),
            ),
          );
      return generated;
    }, clock: _clock);
  }

  Future<void> _upsertAuthored(CurriculumDataset d) {
    return db.batch((b) {
      b.insertAllOnConflictUpdate(db.curriculumDomains, d.curriculumDomains);
      b.insertAllOnConflictUpdate(db.tastingGrids, d.tastingGrids);
      b.insertAllOnConflictUpdate(db.certifications, d.certifications);
      b.insertAllOnConflictUpdate(db.nodeTypes, d.nodeTypes);
      b.insertAllOnConflictUpdate(db.relationTypes, d.relationTypes);
      b.insertAllOnConflictUpdate(
        db.relationTypeSignatures,
        d.relationTypeSignatures,
      );
      b.insertAllOnConflictUpdate(db.knowledgeNodes, d.knowledgeNodes);
      b.insertAllOnConflictUpdate(db.quantityValues, d.quantityValues);
      b.insertAllOnConflictUpdate(
        db.nodeAlternativeNames,
        d.nodeAlternativeNames,
      );
      b.insertAllOnConflictUpdate(db.knowledgeRelations, d.knowledgeRelations);
      b.insertAllOnConflictUpdate(db.knowledgeItems, d.knowledgeItems);
      b.insertAllOnConflictUpdate(
        db.knowledgeItemPrerequisites,
        d.knowledgeItemPrerequisites,
      );
      b.insertAllOnConflictUpdate(
        db.certificationKnowledgeMappings,
        d.certificationKnowledgeMappings,
      );
      b.insertAllOnConflictUpdate(db.sourceCitations, d.sourceCitations);
      b.insertAllOnConflictUpdate(
        db.knowledgeItemCitations,
        d.knowledgeItemCitations,
      );
      b.insertAllOnConflictUpdate(db.questionTemplates, d.questionTemplates);
      b.insertAllOnConflictUpdate(
        db.tastingGridAttributes,
        d.tastingGridAttributes,
      );
      b.insertAllOnConflictUpdate(db.tastingGridValues, d.tastingGridValues);
      b.insertAllOnConflictUpdate(
        db.relationSetAssertions,
        d.relationSetAssertions,
      );
      b.insertAllOnConflictUpdate(db.mapLayers, d.mapLayers);
      b.insertAllOnConflictUpdate(db.mapLayerCitations, d.mapLayerCitations);
      b.insertAllOnConflictUpdate(db.nodeGeometries, d.nodeGeometries);
    });
  }

  /// Authored rows are never deleted (architecture audit V-7), so a release
  /// that drops a row already in the database is refused.
  Future<void> _refuseRemovals(CurriculumDataset d) async {
    final removed = <String>[];
    Future<void> keep<T extends Table, R>(
      TableInfo<T, R> table,
      List<R> incoming,
      String Function(R row) key,
    ) async {
      final kept = {for (final row in incoming) key(row)};
      for (final row in await db.select(table).get()) {
        if (!kept.contains(key(row))) {
          removed.add('${table.actualTableName} ${key(row)}');
        }
      }
    }

    await keep(db.curriculumDomains, d.curriculumDomains, (r) => r.id);
    await keep(db.tastingGrids, d.tastingGrids, (r) => r.id);
    await keep(db.certifications, d.certifications, (r) => r.id);
    await keep(db.nodeTypes, d.nodeTypes, (r) => r.id);
    await keep(db.relationTypes, d.relationTypes, (r) => r.id);
    await keep(
      db.relationTypeSignatures,
      d.relationTypeSignatures,
      (r) => '${r.relationType} ${r.subjectNodeType} ${r.objectNodeType}',
    );
    await keep(db.knowledgeNodes, d.knowledgeNodes, (r) => r.id);
    await keep(db.quantityValues, d.quantityValues, (r) => r.knowledgeNodeId);
    await keep(
      db.nodeAlternativeNames,
      d.nodeAlternativeNames,
      (r) => '${r.knowledgeNodeId} ${r.nameNorm}',
    );
    await keep(
      db.knowledgeRelations,
      d.knowledgeRelations,
      (r) => '${r.subjectId} ${r.relationType} ${r.objectId}',
    );
    await keep(db.knowledgeItems, d.knowledgeItems, (r) => r.id);
    await keep(
      db.knowledgeItemPrerequisites,
      d.knowledgeItemPrerequisites,
      (r) => '${r.knowledgeItemId} ${r.prerequisiteItemId}',
    );
    await keep(
      db.certificationKnowledgeMappings,
      d.certificationKnowledgeMappings,
      (r) => '${r.certificationId} ${r.knowledgeItemId}',
    );
    await keep(db.sourceCitations, d.sourceCitations, (r) => r.id);
    await keep(
      db.knowledgeItemCitations,
      d.knowledgeItemCitations,
      (r) => '${r.knowledgeItemId} ${r.sourceCitationId}',
    );
    await keep(db.questionTemplates, d.questionTemplates, (r) => r.id);
    await keep(
      db.tastingGridAttributes,
      d.tastingGridAttributes,
      (r) => '${r.tastingGridId} ${r.attributeKey}',
    );
    await keep(
      db.tastingGridValues,
      d.tastingGridValues,
      (r) => '${r.tastingGridId} ${r.attributeKey} ${r.valueKey}',
    );
    await keep(
      db.relationSetAssertions,
      d.relationSetAssertions,
      (r) =>
          '${r.nodeId} ${r.relationType} ${r.direction} '
          '${r.memberNodeType} ${r.validFrom}',
    );
    await keep(db.mapLayers, d.mapLayers, (r) => r.id);
    await keep(
      db.mapLayerCitations,
      d.mapLayerCitations,
      (r) => '${r.mapLayerId} ${r.sourceCitationId}',
    );
    await keep(
      db.nodeGeometries,
      d.nodeGeometries,
      (r) => '${r.knowledgeNodeId} ${r.mapLayerId}',
    );

    if (removed.isNotEmpty) {
      throw CurriculumIngestionException(
        'release ${d.version} removes ${removed.length} authored rows; '
        'retire them with valid_until instead: ${removed.take(10).join('; ')}',
      );
    }
  }
}
