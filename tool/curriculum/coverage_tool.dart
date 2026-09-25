import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:sommelier/core/coverage/coverage_baseline.dart';
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_formats.dart';
import 'package:sommelier/core/coverage/coverage_model.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/time/utc_clock.dart';

import 'curriculum_tools.dart';

// The question coverage report and its ratchet (backlog F1,
// docs/design/question-system.md §8):
//
//   dart run tool/coverage_report.dart [--track <id>] [--format md|json]
//       [--update-baseline] [--on <YYYY-MM-DD>] [--dataset <manifest>]
//       [--policy <file>] [--baseline <file>]

/// The date a release is measured on unless told otherwise: the UTC date
/// it was published. The measure then depends on the release alone, not on
/// the day it is taken (audit COV-5).
String releaseDate(CurriculumDataset dataset) =>
    isoDate(dataset.publishedAt.toUtc());

/// Ingests [dataset] into an in-memory database, generating its questions
/// for [on], and measures [tracks], or every selectable track.
Future<List<TrackCoverage>> measureCoverage(
  CurriculumDataset dataset,
  CoveragePolicy policy, {
  required String on,
  List<String>? tracks,
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  try {
    final date = DateTime.parse(on);
    // Local noon, so that ingestion's local date is [on] in any time zone.
    final generation = await CurriculumIngester(
      db,
      clock: Clock.fixed(DateTime(date.year, date.month, date.day, 12)),
    ).ingest(dataset);
    final checker = CoverageChecker(db, policy);
    return [
      for (final id
          in tracks ??
              [for (final track in await checker.selectableTracks()) track.id])
        await checker.check(id, on: on, skipped: generation.skipped),
    ];
  } finally {
    await db.close();
  }
}

/// `coverage_report`: measures the release's question coverage, prints it
/// as Markdown or JSON, and compares it with the committed baseline. Fails
/// when a metric fell below the baseline or a blocking gap is not known.
///
/// With `--update-baseline` it rewrites the baseline's metrics from every
/// selectable track instead, keeping the known gaps that are still open.
Future<int> coverageReport(List<String> args, StringSink out) async {
  const usage =
      'dart run tool/coverage_report.dart [--track <id>] [--format md|json] '
      '[--update-baseline] [--on <YYYY-MM-DD>] [--dataset <manifest>] '
      '[--policy <file>] [--baseline <file>]\n'
      '  --update-baseline measures every selectable track, so it takes no '
      '--track.';
  final options = ToolOptions.parse(
    args,
    named: {'track', 'format', 'on', 'dataset', 'policy', 'baseline'},
    flags: {'update-baseline'},
  );
  final format = options?['format'] ?? 'md';
  final on = options?['on'];
  if (options == null ||
      !const {'md', 'json'}.contains(format) ||
      (on != null && !_isoDate.hasMatch(on)) ||
      (options.has('update-baseline') && options['track'] != null)) {
    return printUsage(out, usage, args);
  }
  final manifest = options['dataset'] ?? curriculumAssetPath;
  final policyPath = options['policy'] ?? coveragePolicyPath(manifest);
  final baselinePath = options['baseline'] ?? coverageBaselinePath(manifest);

  final CurriculumDataset dataset;
  final CoveragePolicy policy;
  try {
    dataset = readDataset(manifest);
    policy = CoveragePolicy.parse(
      File(policyPath).readAsStringSync(),
      path: policyPath,
    );
  } on DatasetFormatException catch (error) {
    out.writeln('error: ${error.message}');
    return exitFailed;
  } on CoveragePolicyException catch (error) {
    out.writeln('error: ${error.message}');
    return exitFailed;
  } on FileSystemException catch (error) {
    out.writeln('error: cannot read ${error.path}: ${error.message}');
    return exitFailed;
  }
  final validation = validateDataset(dataset);
  if (!validation.isValid) {
    out.writeln(
      'The release does not validate; run tool/curriculum/lint.dart:',
    );
    for (final issue in validation.errors) {
      out.writeln('  $issue');
    }
    return exitFailed;
  }

  final date = on ?? releaseDate(dataset);
  final track = options['track'];
  final List<TrackCoverage> tracks;
  try {
    tracks = await measureCoverage(
      dataset,
      policy,
      on: date,
      tracks: track == null ? null : [track],
    );
  } on CoveragePolicyException catch (error) {
    out.writeln('error: the coverage policy does not fit the release:');
    for (final problem in error.problems) {
      out.writeln('  $problem');
    }
    return exitFailed;
  } on ArgumentError {
    out.writeln('error: $track is not a track');
    return exitFailed;
  }

  final baselineFile = File(baselinePath);
  CoverageBaseline? baseline;
  try {
    if (baselineFile.existsSync()) {
      baseline = CoverageBaseline.parse(
        baselineFile.readAsStringSync(),
        path: baselinePath,
      );
    }
  } on CoverageBaselineException catch (error) {
    out.writeln('error: ${error.message}');
    return exitFailed;
  }

  if (options.has('update-baseline')) {
    final CoverageBaseline raised;
    try {
      raised =
          (baseline ??
                  const CoverageBaseline(release: null, on: null, tracks: {}))
              .raisedTo(tracks, release: dataset.version);
    } on CoverageBaselineException catch (error) {
      out.writeln('error: ${error.message}');
      return exitFailed;
    }
    baselineFile
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(raised.toJson());
    final closed = (baseline?.knownGaps.length ?? 0) - raised.knownGaps.length;
    out.writeln(
      'Wrote $baselinePath: ${tracks.length} tracks of release '
      '${dataset.version}, measured on $date; ${raised.knownGaps.length} '
      'known gaps${closed > 0 ? ', $closed closed ones removed' : ''}.',
    );
    return exitOk;
  }

  final ratchet =
      baseline?.check(tracks, allTracks: track == null) ??
      RatchetResult([
        'there is no baseline at $baselinePath: record one with '
            '--update-baseline',
      ], const []);
  if (format == 'json') {
    out.writeln(
      const JsonEncoder.withIndent('  ').convert(
        coverageJson(
          dataset,
          date,
          tracks,
          baseline: baseline,
          ratchet: ratchet,
          baselinePath: baselinePath,
        ),
      ),
    );
  } else {
    out.write(
      coverageMarkdown(
        dataset,
        date,
        tracks,
        baseline: baseline,
        ratchet: ratchet,
        baselinePath: baselinePath,
      ),
    );
  }
  return ratchet.passes ? exitOk : exitFailed;
}

final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// The known gap that accepts [gap], if the baseline has one.
KnownGap? _knownGap(CoverageBaseline? baseline, CoverageGap gap) {
  for (final known in baseline?.knownGaps ?? const <KnownGap>[]) {
    if (known.matches(gap)) return known;
  }
  return null;
}

/// The metrics a report table shows, in order.
const _columns = [
  CoverageMetric.items,
  CoverageMetric.core,
  CoverageMetric.testable,
  CoverageMetric.flashcardOnly,
  CoverageMetric.usefulPractice,
  CoverageMetric.recall,
  CoverageMetric.recognition,
  CoverageMetric.spatial,
  CoverageMetric.structured,
  CoverageMetric.reasoning,
];

/// The report as Markdown: per track, the metrics by domain and area, the
/// policy thresholds and the gaps; then the comparison with the baseline.
String coverageMarkdown(
  CurriculumDataset dataset,
  String on,
  List<TrackCoverage> tracks, {
  required CoverageBaseline? baseline,
  required RatchetResult ratchet,
  required String baselinePath,
}) {
  final out = StringBuffer()
    ..writeln('# Question coverage')
    ..writeln()
    ..writeln(
      'Release ${dataset.version}, measured on $on. Formats built: '
      '${[for (final f in builtFormats.values) '${f.id} (${f.family.name}, ${f.isObjective ? 'objective' : 'self-graded'})'].join(', ')}.',
    )
    ..writeln()
    ..writeln(
      'An item is testable when its track serves it a question. It has '
      'useful practice with an objective format and two families; it is '
      'flashcard-only when the flashcard is all it is served '
      '(question-system §3, audit COV-2).',
    );

  String row(String domain, String area, Map<CoverageMetric, int> counts) =>
      '| $domain | $area | '
      '${[for (final metric in _columns) counts[metric]].join(' | ')} |';

  for (final track in tracks) {
    out
      ..writeln()
      ..writeln('## ${track.trackName} (`${track.trackId}`)')
      ..writeln()
      ..writeln(
        '| Domain | Area | ${[for (final m in _columns) m.label].join(' | ')} |',
      )
      ..writeln('|---|---|${'--:|' * _columns.length}')
      ..writeln(row('**All domains**', '', track.counts.toMap()));
    for (final domain in track.domains) {
      out.writeln(row('**${domain.name}**', '**all**', domain.counts.toMap()));
      for (final MapEntry(key: area, value: counts) in domain.areas.entries) {
        out.writeln(row('', area.name, counts.toMap()));
      }
    }

    final names = {for (final d in track.domains) d.id: d.name};
    out
      ..writeln()
      ..writeln(
        '**Policy thresholds.** Reported now; the release gate (R3) enforces '
        'them (COV-3).',
      )
      ..writeln();
    if (track.thresholds.isEmpty) {
      out.writeln('None.');
    } else {
      out
        ..writeln('| Scope | Metric | Threshold | Measured | Status |')
        ..writeln('|---|---|---|--:|---|');
      for (final result in track.thresholds) {
        final t = result.threshold;
        final measured = t.isPercent
            ? result.base == 0
                  ? 'no ${t.metric.base.key} items'
                  : '${result.value} of ${result.base} '
                        '(${(result.value * 100 / result.base).round()}%)'
            : '${result.value}';
        out.writeln(
          '| ${result.domainId == null ? 'All domains' : names[result.domainId]} '
          '| `${t.metric.key}` | $t | $measured '
          '| ${switch (result.passes) {
            true => 'met',
            false => 'not met',
            null => 'n/a',
          }} |',
        );
      }
    }

    final areaOf = {for (final item in track.items) item.id: item.area.name};
    void gaps(
      String title,
      Iterable<CoverageGap> list,
      String Function(CoverageGap) line,
    ) {
      out
        ..writeln()
        ..writeln(title)
        ..writeln();
      final lines = list.map(line).toList();
      out.writeln(lines.isEmpty ? 'None.' : lines.join('\n'));
    }

    gaps(
      '**Blocking gaps.** The build fails on any that is not a known gap in '
      'the baseline.',
      track.blockingGaps,
      (gap) {
        final known = _knownGap(baseline, gap);
        return '- `${gap.itemId}` (${areaOf[gap.itemId]}): ${gap.kind.label}; '
            '${gap.detail}. '
            '${known == null ? '**Not known.**' : 'Known until ${known.closedBy}: ${known.reason}'}';
      },
    );
    gaps(
      '**Core items without useful practice.**',
      track.gaps.where((g) => g.kind == GapKind.noUsefulPractice),
      (gap) => '- `${gap.itemId}` (${areaOf[gap.itemId]}): ${gap.detail}',
    );
    gaps(
      '**Formats the policy expects that have no question.**',
      track.gaps.where((g) => g.kind == GapKind.missingFormat),
      (gap) =>
          '- `${gap.itemId}` (${areaOf[gap.itemId]}): ${gap.format}: '
          '${gap.detail}',
    );
  }

  out
    ..writeln()
    ..writeln('## Baseline')
    ..writeln()
    ..writeln(
      '`$baselinePath`'
      '${baseline == null ? '' : ', release ${baseline.release}, measured on ${baseline.on}'}: '
      '${ratchet.passes ? '**passes**. No metric fell, and every blocking gap is known.' : '**fails**:'}',
    );
  if (!ratchet.passes) {
    out.writeln();
    for (final failure in ratchet.failures) {
      out.writeln('- $failure');
    }
  }
  if (ratchet.notices.isNotEmpty) {
    out.writeln();
    for (final notice in ratchet.notices) {
      out.writeln('- $notice');
    }
  }
  return '$out';
}

/// The report as JSON, for tools: every metric, threshold, gap and item.
Map<String, Object?> coverageJson(
  CurriculumDataset dataset,
  String on,
  List<TrackCoverage> tracks, {
  required CoverageBaseline? baseline,
  required RatchetResult ratchet,
  required String baselinePath,
}) {
  Map<String, int> counts(CoverageCounts counts) => {
    for (final MapEntry(key: metric, value: count) in counts.toMap().entries)
      metric.key: count,
  };

  return {
    'release': dataset.version,
    'on': on,
    'formats': [
      for (final format in builtFormats.values)
        {
          'id': format.id,
          'family': format.family.name,
          'objective': format.isObjective,
        },
    ],
    'tracks': [
      for (final track in tracks)
        {
          'id': track.trackId,
          'name': track.trackName,
          'total': counts(track.counts),
          'domains': [
            for (final domain in track.domains)
              {
                'id': domain.id,
                'name': domain.name,
                'total': counts(domain.counts),
                'areas': [
                  for (final MapEntry(key: area, value: areaCounts)
                      in domain.areas.entries)
                    {
                      'id': area.id,
                      'name': area.name,
                      'counts': counts(areaCounts),
                    },
                ],
              },
          ],
          'thresholds': [
            for (final result in track.thresholds)
              {
                'domain': result.domainId,
                'metric': result.threshold.metric.key,
                'threshold': '${result.threshold}',
                'value': result.value,
                'base': result.base,
                'passes': result.passes,
              },
          ],
          'gaps': [
            for (final gap in track.gaps)
              {
                'item': gap.itemId,
                'gap': gap.kind.key,
                'blocking': gap.kind.isBlocking,
                'format': gap.format,
                'detail': gap.detail,
                if (_knownGap(baseline, gap) case final known?)
                  'known': {
                    'reason': known.reason,
                    'closed_by': known.closedBy,
                  },
              },
          ],
          'items': [
            for (final item in track.items)
              {
                'id': item.id,
                'relation_type': item.item.relationType,
                'domain': item.item.domainId,
                'area': item.area.id,
                'importance': item.mapping.importance,
                'minimum_depth': item.mapping.minimumDepth,
                'served': [for (final f in item.served) f.questionTemplateId],
                'formats': item.servedFormats.toList(),
                'families': [for (final family in item.families) family.name],
                'useful_practice': item.hasUsefulPractice,
                'missing': item.missing,
              },
          ],
        },
    ],
    'baseline': {
      'path': baselinePath,
      'release': baseline?.release,
      'passes': ratchet.passes,
      'failures': ratchet.failures,
      'notices': ratchet.notices,
    },
  };
}
