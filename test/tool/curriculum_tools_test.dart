import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';

import '../../tool/curriculum/curriculum_tools.dart';
import '../../tool/curriculum/review_ledger.dart';
import '../support/curriculum_fixture.dart';

void main() {
  late Directory temp;
  late String manifest;

  /// The path of a dataset file in the temporary copy, e.g. `areas/x.yaml`.
  String pathOf(String relative) =>
      '${temp.path}/assets/curriculum/$relative'.replaceAll(r'\', '/');

  /// The 1-based line of the first line of [relative] containing [text].
  int lineOf(String relative, String text) =>
      File(pathOf(relative))
          .readAsLinesSync()
          .indexWhere((line) => line.contains(text)) +
      1;

  Future<(int, String)> run(
    Future<int> Function(List<String>, StringSink) tool,
    List<String> args,
  ) async {
    final out = StringBuffer();
    final code = await tool([...args, '--dataset', manifest], out);
    return (code, out.toString());
  }

  setUp(() {
    temp = Directory.systemTemp.createTempSync('curriculum');
    const prefix = 'assets/curriculum/';
    // The scope manifest too: lint requires one for the selectable tracks.
    for (final path in [
      ...bundledDataset().files,
      '${prefix}track_scope.yaml',
    ]) {
      // The copy mirrors the repository, so the manifest's geography path
      // resolves in it.
      final copy = File(
        path.startsWith(prefix)
            ? pathOf(path.substring(prefix.length))
            : '${temp.path}/$path',
      );
      copy.parent.createSync(recursive: true);
      copy.writeAsStringSync(File(path).readAsStringSync());
    }
    manifest = pathOf('curriculum.yaml');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  group('lint', () {
    test('passes on the bundled dataset', () async {
      final (code, out) = await run(lint, []);
      expect(code, exitOk, reason: out);
      expect(
        out,
        contains(
          '${bundledDataset().files.length} files, release '
          '${bundledDataset().version}: 0 errors',
        ),
      );
    });

    test('names the file and line of a broken row', () async {
      final france = File(pathOf('areas/france.yaml'));
      // The first block row naming Burgundy, whatever the line endings of
      // the checkout.
      france.writeAsStringSync(
        france.readAsStringSync().replaceFirst(
          RegExp(r'object_id: n_geo_burgundy(?=\r?\n)'),
          'object_id: n_geo_nowhere',
        ),
      );
      final (code, out) = await run(lint, []);
      expect(code, exitFailed);
      final line = lineOf('areas/france.yaml', '- id: ki_chablis_location');
      expect(
        out,
        contains(
          '${pathOf('areas/france.yaml')}:$line: error: item '
          'ki_chablis_location asserts n_geo_chablis LOCATED_IN '
          'n_geo_nowhere, which is no relation [item-relation]',
        ),
      );
    });

    test('reports a format error with its file and line', () async {
      final italy = File(pathOf('areas/italy.yaml'));
      italy.writeAsStringSync(
        italy.readAsStringSync().replaceFirst(
          'valid_from: "1900-01-01"',
          'valid_from: "1900-02-30"',
        ),
      );
      final (code, out) = await run(lint, []);
      expect(code, exitFailed);
      final line = lineOf('areas/italy.yaml', '1900-02-30');
      expect(out, contains('error: ${pathOf('areas/italy.yaml')}:$line: '));
    });

    test('rejects a verified item that the ledger does not back', () async {
      final france = File(pathOf('areas/france.yaml'));
      final text = france.readAsStringSync();
      final at = text.indexOf('- id: ki_volnay_grape');
      final end = text.indexOf('last_verified_at', at);
      france.writeAsStringSync(
        text.replaceRange(end, end, 'verification_status: verified\n    '),
      );
      final (code, out) = await run(lint, []);
      expect(code, exitFailed);
      expect(
        out,
        contains(
          '${pathOf('areas/france.yaml')}:'
          '${lineOf('areas/france.yaml', '- id: ki_volnay_grape')}: error: '
          'ki_volnay_grape is verified, but the ledger has no review of it '
          '[ledger]',
        ),
      );
    });

    test(
      'rejects what the schema rejects, though the validator does not',
      () async {
        final france = File(pathOf('areas/france.yaml'));
        france.writeAsStringSync(
          france.readAsStringSync().replaceFirst(
            'importance: core',
            'importance: critical',
          ),
        );
        final (code, out) = await run(lint, []);
        expect(code, exitFailed);
        expect(
          out,
          contains('$manifest: error: the release does not ingest: '),
        );
        expect(out, contains('CHECK constraint failed'));
        expect(out, contains('[schema]'));

        final (reportCode, reportOut) = await run(report, []);
        expect(reportCode, exitFailed);
        expect(reportOut, contains('error: the release does not ingest: '));
      },
    );
  });

  test('report prints what the release holds and generates', () async {
    final (code, out) = await run(report, []);
    expect(code, exitOk, reason: out);
    expect(out, contains('Curriculum release ${bundledDataset().version}'));
    expect(out, contains('${pathOf('areas/france.yaml')}: '));
    expect(
      out,
      contains(
        RegExp(r'Questions: \d+ \(\d+ flashcards, \d+ multiple choice\)'),
      ),
    );
    expect(out, contains('mcqDisabled'));
    expect(out, contains('Items with no multiple-choice question:'));
  });

  group('verify', () {
    const review = [
      'ki_chablis_grape',
      '--reviewer',
      'A. Expert, MW',
      '--outcome',
      'verified',
      '--notes',
      'Checked against the cahier des charges, article II.',
      '--at',
      '2026-10-01T09:00:00.000Z',
    ];

    test(
      'records the review and sets the status as a content change',
      () async {
        final before = File(pathOf('areas/france.yaml')).readAsLinesSync();
        final (code, out) = await run(verify, review);
        expect(code, exitOk, reason: out);
        expect(out, contains('Give the release a new dataset_version'));

        // Only the item's two lines changed.
        final after = File(pathOf('areas/france.yaml')).readAsLinesSync();
        expect(after.length, before.length + 1);
        final changed = [
          for (final line in after)
            if (!before.contains(line)) line.trim(),
        ];
        expect(changed, [
          'last_verified_at: "2026-10-01T09:00:00.000Z"',
          'verification_status: verified',
        ]);

        final dataset = readDataset(manifest);
        final item = dataset.knowledgeItems.firstWhere(
          (i) => i.id == 'ki_chablis_grape',
        );
        expect(item.verificationStatus, 'verified');
        expect(item.lastVerifiedAt, DateTime.utc(2026, 10, 1, 9));

        final ledger = ReviewLedger.read(ledgerFolder(manifest));
        final entry = ledger.reviews.single;
        expect(entry.itemId, 'ki_chablis_grape');
        expect(entry.reviewer, 'A. Expert, MW');
        expect(entry.outcome, ReviewOutcome.verified);
        expect(
          entry.notes,
          'Checked against the cahier des charges, article II.',
        );
        expect(entry.location!.path, pathOf('reviews/france.yaml'));

        final (lintCode, lintOut) = await run(lint, []);
        expect(lintCode, exitOk, reason: lintOut);
      },
    );

    test('a disputed review makes the item unverified again', () async {
      await run(verify, review);
      final (code, out) = await run(verify, [
        'ki_chablis_grape',
        '--reviewer',
        'B. Checker, DipWSET',
        '--outcome',
        'disputed',
        '--notes',
        'The 2026 amendment changed the wording.',
        '--at',
        '2026-10-02T09:00:00.000Z',
      ]);
      expect(code, exitOk, reason: out);
      expect(out, contains('Set its verification_status to unverified'));
      final item = readDataset(manifest).knowledgeItems
          .firstWhere((i) => i.id == 'ki_chablis_grape');
      expect(item.verificationStatus, 'unverified');
      expect(
        item.lastVerifiedAt,
        DateTime.utc(2026, 10, 1, 9),
        reason: 'a dispute confirms nothing',
      );
      final ledger = ReviewLedger.read(ledgerFolder(manifest));
      expect(ledger.reviews.map((r) => r.outcome), [
        ReviewOutcome.verified,
        ReviewOutcome.disputed,
      ]);
      expect(
        ledger.latestFor('ki_chablis_grape')!.reviewer,
        'B. Checker, DipWSET',
      );
      final (lintCode, _) = await run(lint, []);
      expect(lintCode, exitOk);
    });

    test('a dispute of an unverified item adds only a review', () async {
      final before = File(pathOf('areas/france.yaml')).readAsStringSync();
      final (code, out) = await run(verify, [
        'ki_chablis_grape',
        '--reviewer',
        'B. Checker, DipWSET',
        '--outcome',
        'disputed',
        '--notes',
        'The locator names the wrong article.',
        '--at',
        '2026-10-02T09:00:00.000Z',
      ]);
      expect(code, exitOk, reason: out);
      expect(out, contains('stays unverified, so the release is unchanged'));
      expect(out, isNot(contains('dataset_version')));
      expect(File(pathOf('areas/france.yaml')).readAsStringSync(), before);
      expect(
        ReviewLedger.read(ledgerFolder(manifest)).reviews.single.outcome,
        ReviewOutcome.disputed,
      );
    });

    test('refuses what it cannot record', () async {
      expect(
        (await run(verify, ['ki_nothing', ...review.skip(1)])).$1,
        exitFailed,
      );
      expect(
        (await run(verify, ['ki_chablis_grape', '--outcome', 'verified'])).$1,
        exitUsage,
        reason: 'no reviewer',
      );
      expect(
        (await run(verify, [
          'ki_chablis_grape',
          '--reviewer',
          'X',
          '--outcome',
          'disputed',
        ])).$1,
        exitUsage,
        reason: 'a dispute needs notes',
      );
      expect(
        (await run(verify, [...review.take(7), '--at', '2026-10-01'])).$1,
        exitUsage,
      );
      await run(verify, review);
      final older = [...review.take(7), '--at', '2026-09-30T09:00:00.000Z'];
      final (code, out) = await run(verify, older);
      expect(code, exitFailed);
      expect(out, contains('older than the last one'));
    });
  });

  group('the review ledger', () {
    test('parses reviews in time order', () {
      final ledger = ReviewLedger.parse('reviews/a.yaml', '''
reviews:
  - knowledge_item_id: ki_a
    reviewer: "A"
    reviewed_at: "2026-10-01T09:00:00.000Z"
    outcome: verified
  - knowledge_item_id: ki_a
    reviewer: "B"
    reviewed_at: "2026-10-02T09:00:00.000Z"
    outcome: disputed
    notes: "Wrong date."
''');
      expect(ledger.reviews, hasLength(2));
      expect(ledger.latestFor('ki_a')!.outcome, ReviewOutcome.disputed);
      expect(
        ledger.reviews.last.location,
        const DatasetLocation('reviews/a.yaml', 6),
      );
      expect(ledger.latestFor('ki_b'), isNull);
      expect(ReviewLedger.parse('r.yaml', 'reviews: []').reviews, isEmpty);
    });

    test('rejects malformed entries, with file and line', () {
      Matcher fails(String message) => throwsA(
        isA<LedgerFormatException>().having(
          (e) => e.message,
          'message',
          contains(message),
        ),
      );
      const entry =
          '  - knowledge_item_id: ki_a\n'
          '    reviewer: "A"\n'
          '    reviewed_at: "2026-10-01T09:00:00.000Z"\n';
      expect(
        () =>
            ReviewLedger.parse('r.yaml', 'reviews:\n$entry    outcome: fine\n'),
        fails('r.yaml:2: outcome must be one of verified, disputed'),
      );
      expect(
        () => ReviewLedger.parse(
          'r.yaml',
          'reviews:\n$entry    outcome: verified\n    score: 5\n',
        ),
        fails('r.yaml:2: unknown keys score'),
      );
      expect(
        () => ReviewLedger.parse(
          'r.yaml',
          'reviews:\n${entry.replaceFirst('.000Z', 'Z')}    outcome: verified\n',
        ),
        fails('is not a UTC instant with milliseconds'),
      );
      expect(
        () => ReviewLedger.parse(
          'r.yaml',
          'reviews:\n$entry    outcome: verified\n'
              '${entry.replaceFirst('10-01', '09-01')}    outcome: verified\n',
        ),
        fails('r.yaml:6: reviews are appended in time order'),
      );
      expect(
        () => ReviewLedger.parse('r.yaml', 'items: []'),
        fails('r.yaml: a ledger file holds one "reviews" list'),
      );
    });
  });

  group('editing an area file', () {
    test('keeps everything but the two columns, in flow rows too', () {
      const flow =
          'knowledge_items:\n'
          '  - { id: ki_a, subject_id: n_a, relation_type: R, object_id: n_b, '
          'domain_id: geography, assertion_text: "A.", '
          'last_verified_at: "2026-01-01T00:00:00.000Z" }\n';
      expect(
        setItemVerification(
          flow,
          'ki_a',
          status: 'verified',
          verifiedAt: DateTime.utc(2026, 10, 1),
        ),
        'knowledge_items:\n'
        '  - { id: ki_a, subject_id: n_a, relation_type: R, object_id: n_b, '
        'domain_id: geography, assertion_text: "A.", '
        'last_verified_at: "2026-10-01T00:00:00.000Z", '
        'verification_status: verified }\n',
      );
    });

    test('replaces a status already written, and keeps CRLF line ends', () {
      const block =
          'knowledge_items:\r\n'
          '  - id: ki_a\r\n'
          '    verification_status: verified\r\n'
          '    last_verified_at: "2026-01-01T00:00:00.000Z"\r\n'
          '    # A note.\r\n'
          '    mcq_disabled: true\r\n';
      expect(
        setItemVerification(block, 'ki_a', status: 'unverified'),
        block.replaceFirst(
          'verification_status: verified',
          'verification_status: unverified',
        ),
      );
      final omitted = block.replaceFirst(
        '    verification_status: verified\r\n',
        '',
      );
      expect(
        setItemVerification(omitted, 'ki_a', status: 'unverified'),
        omitted,
        reason: 'an omitted status is already unverified',
      );
      expect(
        setItemVerification(
          omitted,
          'ki_a',
          status: 'verified',
          verifiedAt: DateTime.utc(2026, 10, 1),
        ),
        'knowledge_items:\r\n'
        '  - id: ki_a\r\n'
        '    last_verified_at: "2026-10-01T00:00:00.000Z"\r\n'
        '    verification_status: verified\r\n'
        '    # A note.\r\n'
        '    mcq_disabled: true\r\n',
      );
    });

    test('appends to an empty ledger file', () {
      final text = appendReview(
        'reviews: []\n',
        Review(
          itemId: 'ki_a',
          reviewer: 'A',
          reviewedAt: DateTime.utc(2026, 10, 1),
          outcome: ReviewOutcome.verified,
        ),
        path: 'reviews/a.yaml',
        area: 'areas/a.yaml',
      );
      expect(
        ReviewLedger.parse('reviews/a.yaml', text).reviews.single.itemId,
        'ki_a',
      );
    });
  });
}
