import 'package:yaml/yaml.dart';

import '../time/utc_clock.dart';
import 'coverage_model.dart';

/// A problem found in the scope manifest: where, and what.
typedef ScopeIssue = ({String at, String message});

/// Thrown when the scope manifest is malformed.
class TrackScopeException implements Exception {
  TrackScopeException(this.problems);

  final List<ScopeIssue> problems;

  String get message =>
      [for (final (:at, :message) in problems) '$at: $message'].join('\n');

  @override
  String toString() => 'Invalid scope manifest:\n$message';
}

/// The official document a track's scope follows, pinned to a version.
final class ScopeSource {
  const ScopeSource({
    required this.title,
    required this.url,
    required this.version,
    required this.checkedOn,
  });

  final String title;
  final String url;

  /// The document's version, as its publisher names it, e.g. `2026/27`.
  final String version;

  /// When the manifest was last compared with the document, `YYYY-MM-DD`.
  final String checkedOn;
}

/// The items that practise an objective: those that meet every condition
/// given. A condition lists alternatives, any one of which matches.
final class ScopeSelector {
  const ScopeSelector({
    this.domains = const {},
    this.within = const {},
    this.relationTypes = const {},
    this.nodeTypes = const {},
  });

  /// Curriculum domain IDs.
  final Set<String> domains;

  /// Node IDs: the item's subject is one of them, or lies inside one.
  final Set<String> within;

  final Set<String> relationTypes;

  /// Node types of the item's subject or object.
  final Set<String> nodeTypes;

  bool matches(ItemCoverage item) =>
      (domains.isEmpty || domains.contains(item.item.domainId)) &&
      (relationTypes.isEmpty ||
          relationTypes.contains(item.item.relationType)) &&
      (nodeTypes.isEmpty ||
          nodeTypes.contains(item.subjectType) ||
          nodeTypes.contains(item.objectType)) &&
      (within.isEmpty || item.places.any(within.contains));
}

/// One objective of a track's official scope, in our own words (D10).
final class ScopeObjective {
  const ScopeObjective({
    required this.id,
    required this.label,
    required this.at,
    this.isRequired = true,
    this.covers,
    this.tasks = const [],
    this.excluded,
  });

  /// A stable editorial ID, e.g. `wset_l3.fortified`.
  final String id;
  final String label;

  /// Where the objective is written: `file:line`.
  final String at;

  /// The scope requires it; otherwise it supports the track.
  final bool isRequired;

  /// The items that practise it, once authored.
  final ScopeSelector? covers;

  /// The backlog tasks that author it.
  final List<String> tasks;

  /// Why it is left out on purpose.
  final String? excluded;
}

/// A track's scope: its official document and its objectives.
final class TrackScope {
  const TrackScope({
    required this.trackId,
    required this.name,
    required this.body,
    required this.source,
    required this.objectives,
    required this.at,
  });

  final String trackId;

  /// The qualification, as its body names it.
  final String name;

  /// The examining body whose document is pinned. A track follows one body
  /// only: CMS_CERTIFIED is CMS Europe's, never CMS Americas'.
  final String body;
  final ScopeSource source;
  final List<ScopeObjective> objectives;

  /// Where the track is written: `file:line`.
  final String at;
}

/// How far the release represents an objective.
enum ObjectiveStatus {
  /// At least one of the track's items practises it.
  represented,

  /// No item practises it yet; a backlog task will author it.
  planned,

  /// Left out on purpose, with a reason.
  excluded,

  /// Required, but no item practises it and no task authors it.
  missing,
}

/// One objective and the track's items that practise it.
final class ObjectiveCoverage {
  const ObjectiveCoverage(
    this.objective, {
    required this.items,
    required this.core,
    required this.usefulPractice,
  });

  final ScopeObjective objective;

  /// The track's items the objective's selector matches.
  final int items;
  final int core;

  /// Matched items with useful practice (audit COV-2).
  final int usefulPractice;

  ObjectiveStatus get status => objective.excluded != null
      ? ObjectiveStatus.excluded
      : items > 0
      ? ObjectiveStatus.represented
      : objective.tasks.isNotEmpty
      ? ObjectiveStatus.planned
      : ObjectiveStatus.missing;
}

/// How [coverage]'s items represent each objective of [scope].
///
/// An objective is represented only by items the release has authored, not
/// by the tasks that plan it: a task mapping alone is no coverage.
List<ObjectiveCoverage> objectiveCoverage(
  TrackScope scope,
  TrackCoverage coverage,
) => [
  for (final objective in scope.objectives)
    () {
      final matched = [
        if (objective.covers case final covers?)
          for (final item in coverage.items)
            if (covers.matches(item)) item,
      ];
      return ObjectiveCoverage(
        objective,
        items: matched.length,
        core: matched.where((item) => item.isCore).length,
        usefulPractice: matched.where((item) => item.hasUsefulPractice).length,
      );
    }(),
];

/// The scope manifest, `assets/curriculum/track_scope.yaml` (backlog
/// SCOPE-1): for each certification track, the objectives of its official
/// scope, and how the curriculum accounts for each.
///
/// Every required objective is covered by items, planned by a task, or
/// excluded with a reason. A syllabus says what a track examines, never
/// that a legal fact is true, so no curriculum item may cite a scope source.
final class TrackScopeManifest {
  const TrackScopeManifest(this.tracks, {this.path = 'track_scope.yaml'});

  /// Parses a manifest. Throws a [TrackScopeException] listing every
  /// problem, each with its file and line.
  factory TrackScopeManifest.parse(
    String text, {
    String path = 'track_scope.yaml',
  }) => _ScopeParser(path).parse(text);

  /// By track ID.
  final Map<String, TrackScope> tracks;

  /// The file the manifest was read from.
  final String path;

  /// Where the manifest does not fit the curriculum and the backlog:
  /// - a track that is not a certification, or a selectable track with no
  ///   scope;
  /// - a selector naming a domain, node, relation type or node type the
  ///   curriculum lacks;
  /// - a task that is not in the backlog, when [tasks] is given;
  /// - a curriculum citation of a scope source ([citedUrls], by citation
  ///   ID).
  List<ScopeIssue> problemsWith({
    required Set<String> tracks,
    required Set<String> selectableTracks,
    required Set<String> domains,
    required Set<String> nodes,
    required Set<String> relationTypes,
    required Set<String> nodeTypes,
    Set<String>? tasks,
    Map<String, String> citedUrls = const {},
  }) {
    final issues = <ScopeIssue>[];
    void unknown(
      ScopeObjective o,
      String kind,
      Set<String> names,
      Set<String> known,
    ) {
      for (final name in names) {
        if (!known.contains(name)) {
          issues.add((at: o.at, message: '${o.id}: unknown $kind "$name"'));
        }
      }
    }

    for (final scope in this.tracks.values) {
      if (!tracks.contains(scope.trackId)) {
        issues.add((
          at: scope.at,
          message: '${scope.trackId} is not a certification track',
        ));
      }
      for (final objective in scope.objectives) {
        if (objective.covers case final covers?) {
          unknown(objective, 'domain', covers.domains, domains);
          unknown(objective, 'node', covers.within, nodes);
          unknown(
            objective,
            'relation type',
            covers.relationTypes,
            relationTypes,
          );
          unknown(objective, 'node type', covers.nodeTypes, nodeTypes);
        }
        if (tasks != null) {
          unknown(objective, 'task', objective.tasks.toSet(), tasks);
        }
      }
    }
    for (final track in selectableTracks.toList()..sort()) {
      if (!this.tracks.containsKey(track)) {
        issues.add((
          at: path,
          message:
              '$track is selectable, but has no scope: pin its official '
              'document and list its objectives',
        ));
      }
    }
    final sources = {
      for (final scope in this.tracks.values)
        _normalized(scope.source.url): scope,
    };
    for (final MapEntry(key: citation, value: url) in citedUrls.entries) {
      if (sources[_normalized(url)] case final scope?) {
        issues.add((
          at: scope.at,
          message:
              'source citation $citation cites the ${scope.trackId} scope '
              'document: a syllabus says what to study, never that a fact is '
              'true',
        ));
      }
    }
    return issues;
  }

  /// The tracks whose document was last compared with the manifest more than
  /// [months] months before [today], `YYYY-MM-DD`.
  List<ScopeIssue> staleSources({required String today, int months = 12}) {
    final now = DateTime.parse(today);
    final cutoff = isoDate(DateTime(now.year, now.month - months, now.day));
    return [
      for (final scope in tracks.values)
        if (scope.source.checkedOn.compareTo(cutoff) < 0)
          (
            at: scope.at,
            message:
                '${scope.trackId}: its ${scope.source.version} document '
                'was last checked on ${scope.source.checkedOn}; compare the '
                'objectives with the current version',
          ),
    ];
  }

  static String _normalized(String url) =>
      url.trim().replaceFirst(RegExp(r'/+$'), '').toLowerCase();
}

class _ScopeParser {
  _ScopeParser(this.path);

  final String path;
  final problems = <ScopeIssue>[];
  final _ids = <String, String>{};

  static final _objectiveId = RegExp(r'^[a-z0-9_]+(\.[a-z0-9_]+)*$');
  static final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static const _selectorKeys = {
    'domains': 'domains',
    'within': 'within',
    'relation_types': 'relation types',
    'node_types': 'node types',
  };

  String _at(YamlNode? node) =>
      node == null ? path : '$path:${node.span.start.line + 1}';

  void _problem(YamlNode? node, String message) =>
      problems.add((at: _at(node), message: message));

  TrackScopeManifest parse(String text) {
    final YamlNode document;
    try {
      document = loadYamlNode(text, sourceUrl: Uri.file(path));
    } on YamlException catch (error) {
      final line = error.span?.start.line;
      throw TrackScopeException([
        (
          at: line == null ? path : '$path:${line + 1}',
          message: 'not valid YAML: ${error.message}',
        ),
      ]);
    }
    final tracks = <String, TrackScope>{};
    if (document is! YamlMap || document.nodes['tracks'] is! YamlMap) {
      throw TrackScopeException([
        (
          at: path,
          message: 'the manifest maps "tracks" to each track\'s scope',
        ),
      ]);
    }
    for (final key in document.nodes.keys.cast<YamlNode>()) {
      if (key.value != 'tracks') _problem(key, 'unknown key "${key.value}"');
    }
    final trackNodes = document.nodes['tracks']! as YamlMap;
    for (final MapEntry(key: key as YamlNode, :value)
        in trackNodes.nodes.entries) {
      if (_track('${key.value}', key, value) case final scope?) {
        tracks[scope.trackId] = scope;
      }
    }
    if (problems.isNotEmpty) throw TrackScopeException(problems);
    return TrackScopeManifest(tracks, path: path);
  }

  /// [node]'s entries, after reporting the keys outside [allowed] and the
  /// missing [required] ones.
  Map<String, YamlNode>? _mapping(
    YamlNode node,
    String what, {
    required Set<String> allowed,
    Set<String> required = const {},
  }) {
    if (node is! YamlMap) {
      _problem(node, '$what must be a mapping');
      return null;
    }
    final entries = {
      for (final MapEntry(:key, :value) in node.nodes.entries)
        '${(key as YamlNode).value}': value,
    };
    for (final key in node.nodes.keys.cast<YamlNode>()) {
      if (!allowed.contains(key.value)) {
        _problem(key, '$what: unknown key "${key.value}"');
      }
    }
    for (final key in required) {
      if (!entries.containsKey(key)) _problem(node, '$what needs "$key"');
    }
    return entries;
  }

  String? _text(YamlNode? node, String what) {
    if (node == null) return null;
    final value = node.value;
    if (value is String && value.trim().isNotEmpty) return value.trim();
    _problem(node, '$what must be text');
    return null;
  }

  Set<String> _names(YamlNode? node, String what) {
    if (node == null) return const {};
    if (node is! YamlList ||
        node.nodes.isEmpty ||
        node.nodes.any((n) => n.value is! String)) {
      _problem(node, '$what must be a list of names');
      return const {};
    }
    return {for (final n in node.nodes) n.value as String};
  }

  TrackScope? _track(String id, YamlNode key, YamlNode node) {
    final entries = _mapping(
      node,
      id,
      allowed: const {'name', 'body', 'source', 'objectives'},
      required: const {'name', 'body', 'source', 'objectives'},
    );
    if (entries == null) return null;
    final source = entries['source'] == null
        ? null
        : _source(id, entries['source']!);
    final objectives = <ScopeObjective>[];
    final list = entries['objectives'];
    if (list != null) {
      if (list is! YamlList || list.nodes.isEmpty) {
        _problem(list, '$id: objectives must be a list of objectives');
      } else {
        for (final objective in list.nodes) {
          if (_objective(id, objective) case final o?) objectives.add(o);
        }
      }
    }
    final name = _text(entries['name'], '$id.name');
    final body = _text(entries['body'], '$id.body');
    if (name == null || body == null || source == null) return null;
    return TrackScope(
      trackId: id,
      name: name,
      body: body,
      source: source,
      objectives: objectives,
      at: _at(key),
    );
  }

  ScopeSource? _source(String track, YamlNode node) {
    final entries = _mapping(
      node,
      '$track.source',
      allowed: const {'title', 'url', 'version', 'checked_on'},
      required: const {'title', 'url', 'version', 'checked_on'},
    );
    if (entries == null) return null;
    final title = _text(entries['title'], '$track.source.title');
    final url = _text(entries['url'], '$track.source.url');
    final version = _text(entries['version'], '$track.source.version');
    final checkedOn = _text(entries['checked_on'], '$track.source.checked_on');
    if (url != null && !RegExp(r'^https?://\S+$').hasMatch(url)) {
      _problem(entries['url'], '$track.source.url is not a web address');
    }
    if (checkedOn != null && !_isDate(checkedOn)) {
      _problem(
        entries['checked_on'],
        '$track.source.checked_on "$checkedOn" is not a YYYY-MM-DD date',
      );
    }
    if (title == null || url == null || version == null || checkedOn == null) {
      return null;
    }
    return ScopeSource(
      title: title,
      url: url,
      version: version,
      checkedOn: checkedOn,
    );
  }

  ScopeObjective? _objective(String track, YamlNode node) {
    final entries = _mapping(
      node,
      '$track objective',
      allowed: const {'id', 'label', 'required', 'covers', 'tasks', 'excluded'},
      required: const {'id', 'label'},
    );
    if (entries == null) return null;
    final id = _text(entries['id'], '$track objective id');
    final label = _text(entries['label'], '${id ?? track} label');
    if (id == null || label == null) return null;
    final at = _at(node);
    if (!_objectiveId.hasMatch(id)) {
      _problem(
        entries['id'],
        '"$id" is not an objective ID: lowercase words joined by _ and .',
      );
    }
    if (_ids[id] case final first?) {
      _problem(entries['id'], '$id is written twice, at $first and $at');
    } else {
      _ids[id] = at;
    }

    final required = entries['required'];
    if (required != null && required.value is! bool) {
      _problem(required, '$id: required must be true or false');
    }
    final covers = entries['covers'] == null
        ? null
        : _selector(id, entries['covers']!);
    final tasks = _names(entries['tasks'], '$id: tasks').toList();
    final excluded = _text(entries['excluded'], '$id: excluded');
    if (excluded != null && (covers != null || tasks.isNotEmpty)) {
      _problem(
        entries['excluded'],
        '$id is excluded, so it can have no covers and no tasks',
      );
    }
    final isRequired = required?.value != false;
    if (isRequired && covers == null && tasks.isEmpty && excluded == null) {
      _problem(
        node,
        '$id is required, but no covers, tasks or excluded accounts for it',
      );
    }
    return ScopeObjective(
      id: id,
      label: label,
      at: at,
      isRequired: isRequired,
      covers: covers,
      tasks: tasks,
      excluded: excluded,
    );
  }

  ScopeSelector? _selector(String id, YamlNode node) {
    final entries = _mapping(
      node,
      '$id: covers',
      allowed: _selectorKeys.keys.toSet(),
    );
    if (entries == null) return null;
    if (entries.isEmpty) {
      _problem(node, '$id: covers needs at least one condition');
      return null;
    }
    Set<String> names(String key) => _names(entries[key], '$id: covers.$key');
    return ScopeSelector(
      domains: names('domains'),
      within: names('within'),
      relationTypes: names('relation_types'),
      nodeTypes: names('node_types'),
    );
  }

  static bool _isDate(String text) {
    if (!_date.hasMatch(text)) return false;
    final parsed = DateTime.tryParse('${text}T12:00:00Z');
    return parsed != null && isoDate(parsed) == text;
  }
}
