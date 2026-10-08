import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';

// Exact map bodies already retained in the immutable predecessor archive.
// Only these two historical paths/hashes differ from the repaired live bundle.
const _historicalSoaveAssets = <String, String>{
  'assets/geography/soave_uga_wikidata_markers.topo.json':
      '58b561ce5e6fdc0cab8468eb717ac2de02dfa97615aee6792740780fbd7289fc',
  'assets/geography/soave_uga_geonames_markers.topo.json':
      'bb39be13e53ca7ea50297721ae2dd76e45099d0a2189fefbb27ac668343fd881',
};
const _archivePath = 'test/fixtures/curriculum_predecessor_pr21_52.json.gz';
const _archiveSha256 =
    'a53df5891100b62fccf04995c741ed24e5b6b4a84b8c3aa08647d9621d3c4fb7';

final _historicalBlobs = _readHistoricalBlobs();

Map<String, dynamic> _readHistoricalBlobs() {
  final bytes = File(_archivePath).readAsBytesSync();
  if (sha256.convert(bytes).toString() != _archiveSha256) {
    throw StateError('Immutable historical map archive integrity mismatch');
  }
  final archive =
      jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
  for (final entry in _historicalSoaveAssets.entries) {
    final retained = (archive['snapshots'] as List<dynamic>).any(
      (snapshot) =>
          ((snapshot as Map<String, dynamic>)['files']
              as Map<String, dynamic>)[entry.key] ==
          entry.value,
    );
    if (!retained) {
      throw StateError('No immutable historical map path/hash: ${entry.key}');
    }
  }
  return archive['blobs'] as Map<String, dynamic>;
}

/// Read map assets for an exact frozen .68/.69/.72 predecessor, never for the
/// current candidate. CurriculumIngester still validates every returned body's
/// SHA and geometry against that predecessor's unmodified manifest.
Future<List<int>> historicalMapAsset(
  CurriculumDataset predecessor,
  String path,
) async {
  if (!{'0.24.68', '0.24.69', '0.24.72'}.contains(predecessor.version)) {
    throw StateError('Historical map loader received a nonhistorical release');
  }
  final expected = predecessor.mapLayers.singleWhere(
    (layer) => layer.assetPath == path,
  );
  final pinned = _historicalSoaveAssets[path];
  if (pinned == null || expected.assetSha256 != pinned) {
    return File(path).readAsBytesSync();
  }
  final bytes = base64Decode(_historicalBlobs[pinned] as String);
  if (sha256.convert(bytes).toString() != pinned) {
    throw StateError('Immutable historical map blob integrity mismatch: $path');
  }
  return bytes;
}
