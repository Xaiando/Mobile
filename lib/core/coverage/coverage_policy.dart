import 'package:yaml/yaml.dart';

import 'coverage_formats.dart';
import 'coverage_model.dart';

/// Thrown when a coverage policy is malformed, or does not fit the
/// curriculum it is checked against.
class CoveragePolicyException implements Exception {
  CoveragePolicyException(this.problems);

  /// Every problem found, each with its place when it has one.
  final List<String> problems;

  String get message => problems.join('\n');

  @override
  String toString() => 'Invalid coverage policy:\n$message';
}

/// The built formats that should test a relation type's items, and why the
/// others should not (question-system §8).
final class RelationCapability {
  const RelationCapability({required this.supports, required this.excludes});

  /// The formats the policy expects for the relation type's items.
  final Set<String> supports;

  /// The formats that do not suit the relation type, each with its reason.
  final Map<String, String> excludes;
}

/// The coverage policy, `assets/curriculum/coverage_policy.yaml`: the
/// formats each relation type should support, the countries split into
/// regional areas, and the thresholds of each track and domain (audit
/// COV-1 to COV-4). It is authored and versioned with the curriculum.
final class CoveragePolicy {
  const CoveragePolicy({
    required this.capabilities,
    this.regionalCountries = const {},
    this.thresholds = const {},
    this.domainThresholds = const {},
    this.trackThresholds = const {},
  });

  /// Parses a policy. Every relation type must say, for each built format,
  /// whether it supports it or why not.
  ///
  /// Every relation type must say how each of [formats] serves it: the
  /// built formats, unless a test gives its own.
  factory CoveragePolicy.parse(
    String text, {
    String path = 'coverage_policy.yaml',
    Iterable<String>? formats,
  }) => _PolicyParser(path, [...formats ?? builtFormats.keys]).parse(text);

  /// By relation type.
  final Map<String, RelationCapability> capabilities;

  /// The countries whose regions are areas; elsewhere the country is.
  final Set<String> regionalCountries;

  /// The thresholds of every track and domain.
  final Map<CoverageMetric, Threshold> thresholds;

  /// Thresholds added to, or replacing, [thresholds] in one domain.
  final Map<String, Map<CoverageMetric, Threshold>> domainThresholds;

  /// Thresholds added to, or replacing, the others on one track.
  final Map<String, Map<CoverageMetric, Threshold>> trackThresholds;

  /// Where the policy does not fit a curriculum with these [relationTypes],
  /// [domains], [tracks] and [nodes]: a relation type it leaves out or does
  /// not know, or a domain, track or node it names that does not exist.
  /// Empty when it fits.
  List<String> problemsWith({
    required Set<String> relationTypes,
    required Set<String> domains,
    required Set<String> tracks,
    required Set<String> nodes,
  }) {
    final listed = capabilities.keys.toSet();
    return [
      for (final type in relationTypes.difference(listed).toList()..sort())
        '$type is not in the coverage policy: say which formats should '
            'test it',
      for (final type in listed.difference(relationTypes).toList()..sort())
        'the coverage policy lists $type, which is not a relation type',
      for (final id in domainThresholds.keys)
        if (!domains.contains(id))
          'the coverage policy sets thresholds for $id, which is not a '
              'domain',
      for (final id in trackThresholds.keys)
        if (!tracks.contains(id))
          'the coverage policy sets thresholds for $id, which is not a track',
      for (final id in regionalCountries)
        if (!nodes.contains(id))
          'regional_countries lists $id, which is not a node',
    ];
  }

  /// The thresholds of [trackId] as a whole, or of its [domainId]: the
  /// policy's own, then the domain's, then the track's, each replacing the
  /// one before for the same metric.
  Map<CoverageMetric, Threshold> thresholdsFor(
    String trackId, [
    String? domainId,
  ]) => {
    ...thresholds,
    if (domainId != null) ...?domainThresholds[domainId],
    ...?trackThresholds[trackId],
  };
}

class _PolicyParser {
  _PolicyParser(this.path, this.formats);

  final String path;

  /// The formats the policy must cover.
  final List<String> formats;
  final problems = <String>[];

  static const _topLevel = {'regional_countries', 'capabilities', 'thresholds'};
  static final _percent = RegExp(r'^(\d+(?:\.\d+)?)%$');

  CoveragePolicy parse(String text) {
    final YamlNode document;
    try {
      document = loadYamlNode(text, sourceUrl: Uri.file(path));
    } on YamlException catch (error) {
      final line = error.span?.start.line;
      throw CoveragePolicyException([
        '$path${line == null ? '' : ':${line + 1}'}: not valid YAML: '
            '${error.message}',
      ]);
    }
    if (document is! YamlMap) {
      throw CoveragePolicyException(['$path: the top level must be a mapping']);
    }
    for (final key in document.nodes.keys.cast<YamlNode>()) {
      if (!_topLevel.contains(key.value)) {
        _problem(key, 'unknown key "${key.value}"');
      }
    }
    final thresholds = _thresholdSection(document.nodes['thresholds']);
    final policy = CoveragePolicy(
      capabilities: _capabilities(document.nodes['capabilities']),
      regionalCountries: _regionalCountries(
        document.nodes['regional_countries'],
      ),
      thresholds: _thresholds('thresholds.all', thresholds?.nodes['all']),
      domainThresholds: _scoped('domains', thresholds?.nodes['domains']),
      trackThresholds: _scoped('tracks', thresholds?.nodes['tracks']),
    );
    if (problems.isNotEmpty) throw CoveragePolicyException(problems);
    return policy;
  }

  void _problem(YamlNode? at, String message) => problems.add(
    at == null
        ? '$path: $message'
        : '$path:${at.span.start.line + 1}: $message',
  );

  Map<String, RelationCapability> _capabilities(YamlNode? node) {
    if (node is! YamlMap) {
      _problem(node, 'capabilities must map each relation type to formats');
      return const {};
    }
    return {
      for (final MapEntry(key: key as YamlNode, :value) in node.nodes.entries)
        '${key.value}': _capability('${key.value}', value),
    };
  }

  RelationCapability _capability(String relationType, YamlNode node) {
    final supports = <String>{};
    final excludes = <String, String>{};
    if (node is! YamlMap) {
      _problem(node, '$relationType must have supports and/or excludes');
      return RelationCapability(supports: supports, excludes: excludes);
    }
    for (final key in node.nodes.keys.cast<YamlNode>()) {
      if (key.value != 'supports' && key.value != 'excludes') {
        _problem(key, '$relationType: unknown key "${key.value}"');
      }
    }
    final supported = node.nodes['supports'];
    if (supported != null) {
      if (supported is! YamlList) {
        _problem(supported, '$relationType: supports must list formats');
      } else {
        for (final format in supported.nodes) {
          if (_format(relationType, format) case final id?) {
            if (!supports.add(id)) {
              _problem(format, '$relationType supports $id twice');
            }
          }
        }
      }
    }
    final excluded = node.nodes['excludes'];
    if (excluded != null) {
      if (excluded is! YamlMap) {
        _problem(
          excluded,
          '$relationType: excludes must map formats to their reasons',
        );
      } else {
        for (final MapEntry(key: format as YamlNode, value: reason)
            in excluded.nodes.entries) {
          final id = _format(relationType, format);
          if (id == null) continue;
          if (reason.value is! String || '${reason.value}'.trim().isEmpty) {
            _problem(reason, '$relationType excludes $id without a reason');
          } else if (supports.contains(id)) {
            _problem(format, '$relationType both supports and excludes $id');
          } else {
            excludes[id] = '${reason.value}'.trim();
          }
        }
      }
    }
    for (final id in formats) {
      if (!supports.contains(id) && !excludes.containsKey(id)) {
        _problem(
          node,
          '$relationType does not say whether $id should test it: list it '
          'under supports, or under excludes with a reason',
        );
      }
    }
    return RelationCapability(supports: supports, excludes: excludes);
  }

  /// The built format [node] names, or null after reporting it.
  String? _format(String relationType, YamlNode node) {
    final id = node.value;
    if (id is String && formats.contains(id)) return id;
    _problem(
      node,
      '$relationType: "$id" is not a built format (${formats.join(', ')})',
    );
    return null;
  }

  Set<String> _regionalCountries(YamlNode? node) {
    if (node == null) return const {};
    if (node is! YamlList || node.nodes.any((n) => n.value is! String)) {
      _problem(node, 'regional_countries must list node IDs');
      return const {};
    }
    return {for (final country in node.nodes) country.value as String};
  }

  YamlMap? _thresholdSection(YamlNode? node) {
    if (node == null) return null;
    if (node is! YamlMap) {
      _problem(node, 'thresholds must be a mapping');
      return null;
    }
    for (final key in node.nodes.keys.cast<YamlNode>()) {
      if (!const {'all', 'domains', 'tracks'}.contains(key.value)) {
        _problem(
          key,
          'thresholds: unknown key "${key.value}" (all, domains or tracks)',
        );
      }
    }
    return node;
  }

  /// Thresholds by domain or track ID, under `thresholds.<key>`.
  Map<String, Map<CoverageMetric, Threshold>> _scoped(
    String key,
    YamlNode? node,
  ) {
    if (node == null) return const {};
    if (node is! YamlMap) {
      _problem(node, 'thresholds.$key must map each ID to its thresholds');
      return const {};
    }
    return {
      for (final MapEntry(key: id as YamlNode, :value) in node.nodes.entries)
        '${id.value}': _thresholds('thresholds.$key.${id.value}', value),
    };
  }

  Map<CoverageMetric, Threshold> _thresholds(String where, YamlNode? node) {
    if (node == null) return const {};
    if (node is! YamlMap) {
      _problem(node, '$where must map metrics to thresholds');
      return const {};
    }
    final thresholds = <CoverageMetric, Threshold>{};
    for (final MapEntry(key: key as YamlNode, :value) in node.nodes.entries) {
      final metric = CoverageMetric.byKey('${key.value}');
      if (metric == null) {
        _problem(key, '$where: unknown metric "${key.value}"');
        continue;
      }
      if (_threshold('$where.${metric.key}', metric, value) case final t?) {
        thresholds[metric] = t;
      }
    }
    return thresholds;
  }

  /// A threshold: `{min: <bound>}` or `{max: <bound>}`, where a bound is a
  /// count or a percentage such as `90%`.
  Threshold? _threshold(String where, CoverageMetric metric, YamlNode node) {
    final bounds = node is YamlMap ? node.nodes : const <Object?, YamlNode>{};
    final keys = {for (final key in bounds.keys) (key as YamlNode).value};
    if (node is! YamlMap ||
        keys.length != 1 ||
        !const {'min', 'max'}.contains(keys.single)) {
      _problem(node, '$where must be {min: <bound>} or {max: <bound>}');
      return null;
    }
    final isMinimum = keys.single == 'min';
    final bound = bounds.values.single;
    final value = bound.value;
    if (value is int && value >= 0) {
      return Threshold(metric, isMinimum: isMinimum, value: value);
    }
    final percent = value is String ? _percent.firstMatch(value) : null;
    final share = percent == null ? null : double.parse(percent[1]!);
    if (share == null || share > 100) {
      _problem(
        bound,
        '$where: "$value" is not a count or a percentage from 0% to 100%',
      );
      return null;
    }
    return Threshold(
      metric,
      isMinimum: isMinimum,
      value: share == share.roundToDouble() ? share.round() : share,
      isPercent: true,
    );
  }
}
