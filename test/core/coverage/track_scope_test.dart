import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/coverage/track_scope.dart';

import 'coverage_fixture.dart';

/// A manifest for [coverageDataset]'s WSET_L2 track.
const scopeText = '''
tracks:
  WSET_L2:
    name: Test Level 2
    body: Test Body
    source:
      title: Test specification
      url: https://example.org/spec.pdf
      version: "2026, Issue 1"
      checked_on: "2026-06-01"
    objectives:
      - id: test.burgundy
        label: Burgundy
        covers: {within: [n_geo_burgundy]}
        tasks: [C2]
      - id: test.germany
        label: Germany
        covers: {within: [n_geo_germany]}
      - id: test.climate_hazards
        label: Hazards of cool climates
        covers: {node_types: [climate], relation_types: [SUSCEPTIBLE_TO]}
      - id: test.viticulture
        label: Viticulture
        covers: {domains: [viticulture]}
      - id: test.spirits
        label: Spirits
        tasks: [C7]
      - id: test.pouring
        label: Pouring at the table
        excluded: A physical skill the app cannot judge.
      - id: test.maps
        label: Map drills
        required: false
''';

Matcher rejects(String message) => throwsA(
  isA<TrackScopeException>().having(
    (e) => [for (final p in e.problems) '${p.at}: ${p.message}'],
    'problems',
    contains(message),
  ),
);

/// [scopeText] with its objectives replaced by [objectives].
String withObjectives(String objectives) =>
    '${scopeText.substring(0, scopeText.indexOf('    objectives:'))}'
    '    objectives:\n$objectives';

void main() {
  test('parses tracks, sources and objectives', () {
    final manifest = TrackScopeManifest.parse(scopeText);
    final scope = manifest.tracks['WSET_L2']!;
    expect(scope.name, 'Test Level 2');
    expect(scope.body, 'Test Body');
    expect(scope.source.version, '2026, Issue 1');
    expect(scope.source.checkedOn, '2026-06-01');
    expect(scope.at, 'track_scope.yaml:2');
    expect(scope.objectives.map((o) => o.id), [
      'test.burgundy',
      'test.germany',
      'test.climate_hazards',
      'test.viticulture',
      'test.spirits',
      'test.pouring',
      'test.maps',
    ]);
    final burgundy = scope.objectives.first;
    expect(burgundy.at, 'track_scope.yaml:11');
    expect(burgundy.covers!.within, {'n_geo_burgundy'});
    expect(burgundy.tasks, ['C2']);
    expect(scope.objectives.last.isRequired, isFalse);
    expect(
      scope.objectives[5].excluded,
      'A physical skill the app cannot judge.',
    );
  });

  group('rejects', () {
    test('a required objective nothing accounts for', () {
      expect(
        () => TrackScopeManifest.parse(
          withObjectives('      - id: test.orphan\n        label: Orphan\n'),
        ),
        rejects(
          'track_scope.yaml:11: test.orphan is required, but no covers, '
          'tasks or excluded accounts for it',
        ),
      );
    });

    test('an ID written twice, naming both places', () {
      expect(
        () => TrackScopeManifest.parse(
          withObjectives(
            '      - id: test.a\n        label: A\n        tasks: [C2]\n'
            '      - id: test.a\n        label: A again\n        tasks: [C2]\n',
          ),
        ),
        rejects(
          'track_scope.yaml:14: test.a is written twice, at '
          'track_scope.yaml:11 and track_scope.yaml:14',
        ),
      );
    });

    test('an excluded objective with covers or tasks', () {
      expect(
        () => TrackScopeManifest.parse(
          withObjectives(
            '      - id: test.a\n        label: A\n        tasks: [C2]\n'
            '        excluded: Not taught.\n',
          ),
        ),
        rejects(
          'track_scope.yaml:14: test.a is excluded, so it can have no covers '
          'and no tasks',
        ),
      );
    });

    test('malformed objectives and selectors', () {
      for (final (objective, problem) in [
        (
          '      - id: Test.A\n        label: A\n        tasks: [C2]\n',
          'track_scope.yaml:11: "Test.A" is not an objective ID: lowercase '
              'words joined by _ and .',
        ),
        (
          '      - id: test.a\n        label: A\n        covers: {places: [x]}\n',
          'track_scope.yaml:13: test.a: covers: unknown key "places"',
        ),
        (
          '      - id: test.a\n        label: A\n        covers: {}\n',
          'track_scope.yaml:13: test.a: covers needs at least one condition',
        ),
        (
          '      - id: test.a\n        label: A\n        tasks: C2\n',
          'track_scope.yaml:13: test.a: tasks must be a list of names',
        ),
        (
          '      - id: test.a\n        label: A\n        required: maybe\n'
              '        tasks: [C2]\n',
          'track_scope.yaml:13: test.a: required must be true or false',
        ),
        (
          '      - id: test.a\n        tasks: [C2]\n',
          'track_scope.yaml:11: WSET_L2 objective needs "label"',
        ),
      ]) {
        expect(
          () => TrackScopeManifest.parse(withObjectives(objective)),
          rejects(problem),
          reason: objective,
        );
      }
    });

    test('a source without its pinned version, or with a bad date or URL', () {
      expect(
        () => TrackScopeManifest.parse(
          scopeText.replaceFirst('      version: "2026, Issue 1"\n', ''),
        ),
        rejects('track_scope.yaml:6: WSET_L2.source needs "version"'),
      );
      expect(
        () => TrackScopeManifest.parse(
          scopeText.replaceFirst('"2026-06-01"', '"2026-02-30"'),
        ),
        rejects(
          'track_scope.yaml:9: WSET_L2.source.checked_on "2026-02-30" is not '
          'a YYYY-MM-DD date',
        ),
      );
      expect(
        () => TrackScopeManifest.parse(
          scopeText.replaceFirst('https://example.org/spec.pdf', 'spec.pdf'),
        ),
        rejects('track_scope.yaml:7: WSET_L2.source.url is not a web address'),
      );
    });

    test('an unknown key, or text that is not YAML', () {
      expect(
        () => TrackScopeManifest.parse('$scopeText\nversion: 2\n'),
        rejects('track_scope.yaml:34: unknown key "version"'),
      );
      expect(
        () => TrackScopeManifest.parse('tracks: [', path: 's.yaml'),
        throwsA(
          isA<TrackScopeException>().having(
            (e) => e.message,
            'message',
            startsWith('s.yaml:1: not valid YAML'),
          ),
        ),
      );
    });
  });

  group('against the curriculum and the backlog', () {
    final manifest = TrackScopeManifest.parse(scopeText);
    List<String> problems({
      Set<String> tracks = const {'WSET_L1', 'WSET_L2'},
      Set<String> selectable = const {'WSET_L2'},
      Set<String> domains = const {'geography', 'viticulture'},
      Set<String> nodes = const {'n_geo_burgundy', 'n_geo_germany'},
      Set<String> relationTypes = const {'SUSCEPTIBLE_TO'},
      Set<String> nodeTypes = const {'climate'},
      Set<String>? tasks = const {'C2', 'C7'},
      Map<String, String> citedUrls = const {},
    }) => [
      for (final (:at, :message) in manifest.problemsWith(
        tracks: tracks,
        selectableTracks: selectable,
        domains: domains,
        nodes: nodes,
        relationTypes: relationTypes,
        nodeTypes: nodeTypes,
        tasks: tasks,
        citedUrls: citedUrls,
      ))
        '$at: $message',
    ];

    test('fits', () => expect(problems(), isEmpty));

    test('names an unknown area or task', () {
      expect(problems(nodes: {'n_geo_burgundy'}), [
        'track_scope.yaml:15: test.germany: unknown node "n_geo_germany"',
      ]);
      expect(problems(domains: {'geography'}), [
        'track_scope.yaml:21: test.viticulture: unknown domain "viticulture"',
      ]);
      expect(problems(relationTypes: {}, nodeTypes: {}), [
        'track_scope.yaml:18: test.climate_hazards: unknown relation type '
            '"SUSCEPTIBLE_TO"',
        'track_scope.yaml:18: test.climate_hazards: unknown node type '
            '"climate"',
      ]);
      expect(problems(tasks: {'C2'}), [
        'track_scope.yaml:24: test.spirits: unknown task "C7"',
      ]);
      expect(problems(tasks: null), isEmpty, reason: 'no backlog to check');
    });

    test('needs a scope for each selectable track, and only for tracks', () {
      expect(problems(selectable: {'WSET_L2', 'CMS_CERTIFIED'}), [
        'track_scope.yaml: CMS_CERTIFIED is selectable, but has no scope: pin '
            'its official document and list its objectives',
      ]);
      expect(problems(tracks: {'WSET_L1'}), [
        'track_scope.yaml:2: WSET_L2 is not a certification track',
      ]);
    });

    test('refuses a syllabus as a fact\'s source', () {
      expect(
        problems(citedUrls: {'src_syllabus': 'https://EXAMPLE.org/spec.pdf/'}),
        [
          'track_scope.yaml:2: source citation src_syllabus cites the WSET_L2 '
              'scope document: a syllabus says what to study, never that a '
              'fact is true',
        ],
      );
    });
  });

  test('warns when a document was last checked more than a year ago', () {
    final manifest = TrackScopeManifest.parse(scopeText);
    expect(manifest.staleSources(today: '2027-06-01'), isEmpty);
    expect(
      [
        for (final (:at, :message) in manifest.staleSources(
          today: '2027-06-02',
        ))
          '$at: $message',
      ],
      [
        'track_scope.yaml:2: WSET_L2: its 2026, Issue 1 document was last '
            'checked on 2026-06-01; compare the objectives with the current '
            'version',
      ],
    );
  });

  test('an objective is represented only by the items it covers', () async {
    final coverage = await coverageOf(coverageDataset());
    final scope = TrackScopeManifest.parse(scopeText).tracks['WSET_L2']!;
    expect(
      {
        for (final o in objectiveCoverage(scope, coverage))
          o.objective.id:
              '${o.status.name} ${o.items} items, ${o.core} core, '
              '${o.usefulPractice} useful',
      },
      {
        'test.burgundy': 'represented 4 items, 3 core, 1 useful',
        'test.germany': 'represented 1 items, 1 core, 1 useful',
        'test.climate_hazards': 'represented 1 items, 1 core, 0 useful',
        'test.viticulture': 'represented 1 items, 1 core, 0 useful',
        'test.spirits': 'planned 0 items, 0 core, 0 useful',
        'test.pouring': 'excluded 0 items, 0 core, 0 useful',
        'test.maps': 'missing 0 items, 0 core, 0 useful',
      },
      reason:
          'Germany is reached through Ahr; the climate item matches its '
          'subject type and its relation type',
    );
  });

  test('selectors need every condition, and any value of each', () async {
    final coverage = await coverageOf(coverageDataset());
    int matching(ScopeSelector selector) =>
        coverage.items.where(selector.matches).length;
    expect(matching(const ScopeSelector(domains: {'geography'})), 6);
    expect(
      matching(
        const ScopeSelector(
          domains: {'geography'},
          within: {'n_geo_beaujolais', 'n_geo_germany'},
        ),
      ),
      2,
    );
    expect(
      matching(const ScopeSelector(nodeTypes: {'hazard'})),
      1,
      reason: 'the object\'s node type counts too',
    );
    expect(
      matching(
        const ScopeSelector(domains: {'geography'}, nodeTypes: {'hazard'}),
      ),
      0,
    );
    final item = coverage.items.firstWhere((i) => i.id == 'ki_chablis_grape');
    expect(item.places, {'n_geo_chablis', 'n_geo_burgundy', 'n_geo_france'});
    expect(item.subjectType, 'appellation');
    expect(item.objectType, 'grape');
  });
}
