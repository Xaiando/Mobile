import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/curriculum/coverage_tool.dart';
import '../../tool/curriculum/curriculum_tools.dart';
import '../support/curriculum_fixture.dart';

void main() {
  late Directory temp;
  late String manifest;

  String pathOf(String relative) =>
      '${temp.path}/$relative'.replaceAll(r'\', '/');

  Future<(int, String)> run(List<String> args) async {
    final out = StringBuffer();
    final code = await coverageReport([...args, '--dataset', manifest], out);
    return (code, '$out');
  }

  /// The copy's policy without [relationType]'s capabilities.
  void dropFromPolicy(String relationType) {
    final policy = File(pathOf('coverage_policy.yaml'));
    policy.writeAsStringSync(
      policy
          .readAsStringSync()
          .replaceAll('\r\n', '\n')
          .replaceFirst(
            RegExp('  $relationType:\n    supports: \\[flashcard, mcq\\]\n'),
            '',
          ),
    );
  }

  setUp(() {
    temp = Directory.systemTemp.createTempSync('coverage');
    const prefix = 'assets/curriculum/';
    for (final path in [
      ...bundledDataset().files,
      '${prefix}coverage_policy.yaml',
      '${prefix}coverage_baseline.json',
      '${prefix}track_scope.yaml',
    ]) {
      final copy = File(pathOf(path.substring(prefix.length)));
      copy.parent.createSync(recursive: true);
      copy.writeAsStringSync(File(path).readAsStringSync());
    }
    manifest = pathOf('curriculum.yaml');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('prints the report, which passes the committed baseline', () async {
    final (code, out) = await run([]);
    expect(code, exitOk, reason: out);
    expect(out, contains('# Question coverage'));
    expect(out, contains('## WSET Level 3 (`WSET_L3`)'));
    expect(out, contains('## CMS Certified Sommelier (`CMS_CERTIFIED`)'));
    expect(
      out,
      contains(
        '| Domain | Area | Items | Core | Testable | Flashcard-only | '
        'Useful practice | Recall | Recognition | Spatial | Structured | '
        'Reasoning |',
      ),
    );
    expect(out, contains('Known until Q1'));
    expect(out, contains('**passes**'));
    expect(out, contains('(question-system §3, audit COV-2).'));
  });

  test('prints one track as JSON', () async {
    final (code, out) = await run(['--track', 'WSET_L3', '--format', 'json']);
    expect(code, exitOk, reason: out);
    final json = jsonDecode(out) as Map<String, dynamic>;
    expect(json['release'], bundledDataset().version);
    final tracks = json['tracks'] as List<dynamic>;
    expect(tracks.map((t) => (t as Map)['id']), ['WSET_L3']);
    final track = tracks.single as Map<String, dynamic>;
    expect((track['total'] as Map)['items'], greaterThan(0));
    expect(track['items'], isNotEmpty);
    expect((json['baseline'] as Map)['passes'], isTrue);
  });

  test('fails when coverage falls below the baseline', () async {
    final baseline = File(pathOf('coverage_baseline.json'));
    baseline.writeAsStringSync(
      baseline.readAsStringSync().replaceFirst(
        RegExp(r'"testable": \d+'),
        '"testable": 999',
      ),
    );
    final (code, out) = await run([]);
    expect(code, exitFailed);
    expect(out, contains('**fails**'));
    expect(out, contains('CMS_CERTIFIED: testable fell from 999 to'));
  });

  test('fails without a baseline', () async {
    File(pathOf('coverage_baseline.json')).deleteSync();
    final (code, out) = await run([]);
    expect(code, exitFailed);
    expect(out, contains('there is no baseline at'));
  });

  test(
    '--update-baseline records the coverage and keeps the known gaps',
    () async {
      final baseline = File(pathOf('coverage_baseline.json'));
      final committed = baseline.readAsStringSync().replaceAll('\r\n', '\n');
      baseline.writeAsStringSync(
        committed.replaceFirst(RegExp(r'"testable": \d+'), '"testable": 999'),
      );
      final (code, out) = await run(['--update-baseline']);
      expect(code, exitOk, reason: out);
      expect(out, contains('5 known gaps'));
      expect(baseline.readAsStringSync(), committed);
      expect((await run([])).$1, exitOk);
    },
  );

  test('refuses a policy that leaves out a relation type', () async {
    dropFromPolicy('LOCATED_IN');
    final (code, out) = await run([]);
    expect(code, exitFailed);
    expect(
      out,
      contains(
        'LOCATED_IN is not in the coverage policy: say which formats should '
        'test it',
      ),
    );
  });

  test('refuses what it cannot do', () async {
    expect((await run(['--format', 'xml'])).$1, exitUsage);
    for (final date in ['2026-9-1', '2026-02-31', '2026-99-99']) {
      expect((await run(['--on', date])).$1, exitUsage, reason: date);
    }
    expect(
      (await run(['--update-baseline', '--track', 'WSET_L3'])).$1,
      exitUsage,
      reason: '--update-baseline measures every track',
    );
    final (code, out) = await run(['--track', 'WSET_L9']);
    expect(code, exitFailed);
    expect(out, contains('WSET_L9 is not a track'));
  });

  group('scope objectives (SCOPE-1)', () {
    test('are reported for each track, as Markdown and JSON', () async {
      final (code, out) = await run([]);
      expect(code, exitOk, reason: out);
      expect(out, contains('**Scope objectives** (SCOPE-1). '));
      expect(
        out,
        contains(RegExp(r'\d+ required objectives: \d+ represented, ')),
      );
      expect(
        out,
        contains(
          RegExp(
            r'\| `wset_l3\.still\.burgundy` [^|]+\| \d+ \| \d+ \| \d+ '
            r'\| represented \|',
          ),
        ),
      );
      expect(out, contains('| planned: C7 |'));
      expect(out, contains('excluded: The practical examination'));

      final (_, json) = await run(['--format', 'json', '--track', 'WSET_L3']);
      final track = ((jsonDecode(json) as Map)['tracks'] as List).single as Map;
      final scope = track['scope'] as Map;
      expect((scope['source'] as Map)['version'], '2022, Issue 2');
      final objectives = scope['objectives'] as List;
      expect(
        objectives.map((o) => (o as Map)['status']).toSet(),
        containsAll(['represented', 'planned']),
      );
    });

    test(
      'lint checks the manifest against the release and the backlog',
      () async {
        final scope = File(pathOf('track_scope.yaml'));
        scope.writeAsStringSync(
          scope
              .readAsStringSync()
              .replaceFirst('tasks: [C7]', 'tasks: [Z9]')
              .replaceFirst(
                'checked_on: "2026-09-25"',
                'checked_on: "2020-01-01"',
              ),
        );
        final out = StringBuffer();
        expect(await lint(['--dataset', manifest], out), exitFailed);
        expect(
          '$out',
          contains(
            RegExp(
              r'track_scope\.yaml:\d+: error: cms_certified\.spirits: '
              r'unknown task "Z9" \[scope\]',
            ),
          ),
        );
        expect(
          '$out',
          contains(
            RegExp(
              r'track_scope\.yaml:\d+: warning: WSET_L3: its 2022, '
              r'Issue 2 document was last checked on 2020-01-01',
            ),
          ),
        );
      },
    );

    test('lint refuses a syllabus cited as a fact\'s source', () async {
      final france = File(pathOf('areas/france.yaml'));
      france.writeAsStringSync(
        france.readAsStringSync().replaceFirst(
          RegExp(r'url: "?https://www\.inao\.gouv\.fr[^\s",}]*"?'),
          'url: "https://courtofmastersommeliers.org/wp-content/uploads/2026/'
          '02/Syllabus-202627-1.pdf"',
        ),
      );
      final out = StringBuffer();
      expect(await lint(['--dataset', manifest], out), exitFailed);
      expect(
        '$out',
        contains(
          'cites the CMS_CERTIFIED scope document: a syllabus says '
          'what to study, never that a fact is true [scope]',
        ),
      );
    });

    test('lint fails when the manifest is missing', () async {
      File(pathOf('track_scope.yaml')).deleteSync();
      final out = StringBuffer();
      expect(await lint(['--dataset', manifest], out), exitFailed);
      for (final track in ['CMS_CERTIFIED', 'WSET_L3']) {
        expect(
          '$out',
          contains(
            '${pathOf('track_scope.yaml')}: error: $track is selectable, but '
            'has no scope: pin its official document and list its '
            'objectives [scope]',
          ),
        );
      }
    });

    test('the report refuses a scope that does not fit the release', () async {
      final scope = File(pathOf('track_scope.yaml'));
      scope.writeAsStringSync(
        scope.readAsStringSync().replaceFirst(
          'within: [n_geo_burgundy]',
          'within: [n_geo_nowhere]',
        ),
      );
      final (code, out) = await run([]);
      expect(code, exitFailed);
      expect(
        out,
        contains('error: the scope manifest does not fit the release:'),
      );
      expect(
        out,
        contains(
          RegExp(
            r'track_scope\.yaml:\d+: wset_l3\.[a-z_.]+: unknown node '
            r'"n_geo_nowhere"',
          ),
        ),
      );
    });

    test('the report needs a scope manifest', () async {
      File(pathOf('track_scope.yaml')).deleteSync();
      final (code, out) = await run([]);
      expect(code, exitFailed);
      expect(out, contains('error: cannot read ${pathOf('track_scope.yaml')}'));

      final (other, otherOut) = await run(['--scope', pathOf('none.yaml')]);
      expect(other, exitFailed);
      expect(otherOut, contains('error: cannot read ${pathOf('none.yaml')}'));
    });
  });

  group('the curriculum tools', () {
    test('lint checks the coverage policy against the release', () async {
      dropFromPolicy('HAS_SOIL');
      final out = StringBuffer();
      expect(await lint(['--dataset', manifest], out), exitFailed);
      expect(
        '$out',
        contains(
          '${pathOf('coverage_policy.yaml')}: error: HAS_SOIL is not in the '
          'coverage policy: say which formats should test it '
          '[coverage-policy]',
        ),
      );
    });

    test('report ends with the coverage of each track', () async {
      final out = StringBuffer();
      expect(await report(['--dataset', manifest], out), exitOk);
      expect(
        '$out',
        contains('Coverage on ${releaseDate(bundledDataset())} '),
        reason: 'coverage is measured on the release date (COV-5)',
      );
      for (final track in ['CMS_CERTIFIED', 'WSET_L3']) {
        expect(
          '$out',
          contains(
            RegExp(
              '  $track: \\d+ items \\(\\d+ core\\), \\d+ testable, \\d+ '
              'flashcard-only, \\d+ with useful practice; \\d+ blocking '
              'gaps, \\d+ known',
            ),
          ),
        );
      }
    });
  });
}
