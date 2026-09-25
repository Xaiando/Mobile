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
