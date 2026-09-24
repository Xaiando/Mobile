import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_providers.dart';
import '../time/time_providers.dart';
import 'curriculum_catalog.dart';
import 'curriculum_dataset.dart';
import 'curriculum_ingestion.dart';
import 'knowledge_graph.dart';

/// Reads and parses the bundled curriculum dataset: its manifest, then each
/// file the manifest includes.
///
/// `rootBundle.loadString` would decode a file this size in a background
/// isolate; decoding a few dozen kilobytes directly is faster and behaves the
/// same on every platform.
Future<CurriculumDataset> loadBundledCurriculum() =>
    CurriculumDataset.load(curriculumAssetPath, (path) async {
      final data = await rootBundle.load(path);
      return utf8.decode(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    });

/// The dataset startup ingests. Tests override it.
final curriculumSourceProvider = Provider<Future<CurriculumDataset> Function()>(
  (ref) => loadBundledCurriculum,
);

final curriculumIngesterProvider = Provider<CurriculumIngester>(
  (ref) => CurriculumIngester(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
  ),
);

final knowledgeGraphProvider = Provider<KnowledgeGraph>(
  (ref) => KnowledgeGraph(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
  ),
);

final curriculumCatalogProvider = Provider<CurriculumCatalog>(
  (ref) => CurriculumCatalog(ref.watch(appDatabaseProvider)),
);
