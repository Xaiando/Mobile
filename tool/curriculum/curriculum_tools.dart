import 'dart:io';

import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:sommelier/core/coverage/coverage_baseline.dart';
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_model.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/coverage/track_scope.dart';
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/question_generator.dart';
import 'package:sommelier/core/time/utc_clock.dart';
import 'package:yaml/yaml.dart';

import 'review_ledger.dart';

// The curriculum authoring tools (backlog C1). Each runs with `dart run`
// from the repository root:
//
//   dart run tool/curriculum/lint.dart     every problem, with file and line
//   dart run tool/curriculum/report.dart   what ingestion generates
//   dart run tool/curriculum/verify.dart   record an expert's review
//
// tool/coverage_report.dart reports question coverage (backlog F1).

/// Exit codes: success, problems found, and a usage error.
const exitOk = 0, exitFailed = 1, exitUsage = 64;

/// Reads the dataset whose manifest is at [manifest] from disk.
CurriculumDataset readDataset(String manifest) => CurriculumDataset.loadSync(
  manifest,
  (path) => File(path).readAsStringSync(),
);

/// The path of [name] in [manifest]'s folder.
String besideManifest(String manifest, String name) {
  final path = manifest.replaceAll(r'\', '/');
  final slash = path.lastIndexOf('/');
  return slash < 0 ? name : '${path.substring(0, slash)}/$name';
}

/// The date a release is measured on unless told otherwise: the UTC date
/// it was published. What `report` and `coverage_report` measure then
/// depends on the release alone, not on the day they run (audit COV-5).
String releaseDate(CurriculumDataset dataset) =>
    isoDate(dataset.publishedAt.toUtc());

/// Whether [text] is a date, `YYYY-MM-DD`, that the calendar has.
bool isCalendarDate(String text) {
  final parsed = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)
      ? DateTime.tryParse('${text}T12:00:00Z')
      : null;
  return parsed != null && isoDate(parsed) == text;
}

/// A clock stopped at local noon on [date], `YYYY-MM-DD`, so that
/// ingestion generates the questions for that date in any time zone.
Clock clockOn(String date) {
  final day = DateTime.parse(date);
  return Clock.fixed(DateTime(day.year, day.month, day.day, 12));
}

/// The review ledger's folder: `reviews/` next to [manifest].
String ledgerFolder(String manifest) => besideManifest(manifest, 'reviews');

/// The coverage policy next to [manifest].
String coveragePolicyPath(String manifest) =>
    besideManifest(manifest, 'coverage_policy.yaml');

/// The coverage baseline next to [manifest].
String coverageBaselinePath(String manifest) =>
    besideManifest(manifest, 'coverage_baseline.json');

/// The coverage policy at [path], or null if there is none.
CoveragePolicy? readCoveragePolicy(String path) {
  final file = File(path);
  return file.existsSync()
      ? CoveragePolicy.parse(file.readAsStringSync(), path: path)
      : null;
}

/// Where the coverage [policy] does not fit [dataset]
/// ([CoveragePolicy.problemsWith]).
List<String> coveragePolicyProblems(
  CoveragePolicy policy,
  CurriculumDataset dataset,
) => policy.problemsWith(
  relationTypes: {for (final type in dataset.relationTypes) type.id},
  domains: {for (final domain in dataset.curriculumDomains) domain.id},
  tracks: {for (final track in dataset.certifications) track.id},
  nodes: {for (final node in dataset.knowledgeNodes) node.id},
);

/// The scope manifest next to [manifest] (backlog SCOPE-1).
String trackScopePath(String manifest) =>
    besideManifest(manifest, 'track_scope.yaml');

/// The scope manifest at [path]. Without a file it is empty, so every
/// selectable track lacks a scope, which [trackScopeProblems] reports.
TrackScopeManifest readTrackScope(String path) {
  final file = File(path);
  return file.existsSync()
      ? TrackScopeManifest.parse(file.readAsStringSync(), path: path)
      : TrackScopeManifest(const {}, path: path);
}

/// The task IDs of the backlog at [path], from its task index, or null if
/// there is no backlog there.
Set<String>? backlogTasks(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final row = RegExp(
    r'^\|\s*([A-Z][A-Z0-9]*(?:-[0-9]+)?)\s*\|',
    multiLine: true,
  );
  return {
    for (final match in row.allMatches(file.readAsStringSync())) match[1]!,
  };
}

/// Where the [scope] manifest does not fit [dataset], and the backlog's
/// [tasks] when they are known ([TrackScopeManifest.problemsWith]).
List<ScopeIssue> trackScopeProblems(
  TrackScopeManifest scope,
  CurriculumDataset dataset, {
  Set<String>? tasks,
}) => scope.problemsWith(
  tracks: {for (final track in dataset.certifications) track.id},
  selectableTracks: {
    for (final track in dataset.certifications)
      if (track.isSelectable) track.id,
  },
  domains: {for (final domain in dataset.curriculumDomains) domain.id},
  nodes: {for (final node in dataset.knowledgeNodes) node.id},
  relationTypes: {for (final type in dataset.relationTypes) type.id},
  nodeTypes: {for (final type in dataset.nodeTypes) type.id},
  tasks: tasks,
  citedUrls: {
    for (final source in dataset.sourceCitations) source.id: ?source.url,
  },
);

/// Why [dataset] cannot be ingested into a new database, or null if it can.
///
/// Ingestion also enforces the schema's own constraints, which the validator
/// does not repeat: the allowed values of `importance` or
/// `verification_status`, the range of `minimum_depth`, and so on.
Future<String?> ingestionProblem(CurriculumDataset dataset) async {
  final db = AppDatabase(NativeDatabase.memory());
  try {
    await CurriculumIngester(db).ingest(dataset);
    return null;
  } on Exception catch (error) {
    return 'the release does not ingest: $error';
  } finally {
    await db.close();
  }
}

/// `lint`: prints every problem of the dataset as `file:line: kind: message
/// [rule]`: format errors, the validator's errors and warnings, ledger
/// errors, a coverage policy that does not fit the release, and the scope
/// manifest's problems (a selectable track without a scope, even when the
/// manifest is missing) and stale sources. A release without them must also
/// ingest, so that the schema's constraints hold. Fails if there is any
/// error.
Future<int> lint(
  List<String> args,
  StringSink out, {
  Clock clock = const Clock(),
}) async {
  const usage =
      'dart run tool/curriculum/lint.dart [--dataset <manifest>] '
      '[--backlog <file>]';
  final options = ToolOptions.parse(args, named: {'dataset', 'backlog'});
  if (options == null) return printUsage(out, usage, args);
  final manifest = options['dataset'] ?? curriculumAssetPath;
  final backlog = options['backlog'] ?? 'docs/backlog.md';

  final CurriculumDataset dataset;
  try {
    dataset = readDataset(manifest);
  } on DatasetFormatException catch (error) {
    out.writeln('error: ${error.message}');
    return exitFailed;
  }

  var errors = 0, warnings = 0;
  for (final issue in validateDataset(dataset).issues) {
    final row = issue.row;
    final at = (row == null ? null : dataset.locate(row)) ?? manifest;
    out.writeln(
      '$at: ${issue.isError ? 'error' : 'warning'}: ${issue.message} '
      '[${issue.rule}]',
    );
    if (issue.isError) {
      errors++;
    } else {
      warnings++;
    }
  }
  // The map assets match their manifest (backlog G2), as ingestion checks.
  for (final problem in await mapAssetProblems(
    dataset,
    (path) async => File(path).readAsBytesSync(),
  )) {
    out.writeln('$manifest: error: $problem [map-asset]');
    errors++;
  }
  try {
    final ledger = ReviewLedger.read(ledgerFolder(manifest));
    for (final problem in ledgerProblems(dataset, ledger)) {
      out.writeln(problem);
      errors++;
    }
  } on LedgerFormatException catch (error) {
    out.writeln('error: ${error.message}');
    errors++;
  }
  // The design's dataset validation: every relation type is in the policy.
  final policyPath = coveragePolicyPath(manifest);
  try {
    if (readCoveragePolicy(policyPath) case final policy?) {
      for (final problem in coveragePolicyProblems(policy, dataset)) {
        out.writeln('$policyPath: error: $problem [coverage-policy]');
        errors++;
      }
    }
  } on CoveragePolicyException catch (error) {
    for (final problem in error.problems) {
      out.writeln('error: $problem [coverage-policy]');
      errors++;
    }
  }
  final scopePath = trackScopePath(manifest);
  try {
    final scope = readTrackScope(scopePath);
    final tasks = backlogTasks(backlog);
    if (tasks == null) {
      out.writeln(
        '$scopePath: warning: no backlog at $backlog, so tasks are not '
        'checked [scope]',
      );
      warnings++;
    }
    for (final (:at, :message) in trackScopeProblems(
      scope,
      dataset,
      tasks: tasks,
    )) {
      out.writeln('$at: error: $message [scope]');
      errors++;
    }
    for (final (:at, :message) in scope.staleSources(
      today: localToday(clock),
    )) {
      out.writeln('$at: warning: $message [scope]');
      warnings++;
    }
  } on TrackScopeException catch (error) {
    for (final (:at, :message) in error.problems) {
      out.writeln('$at: error: $message [scope]');
      errors++;
    }
  }
  if (errors == 0) {
    if (await ingestionProblem(dataset) case final problem?) {
      out.writeln('$manifest: error: $problem [schema]');
      errors++;
    }
  }
  out.writeln(
    '${dataset.files.length} files, release ${dataset.version}: '
    '$errors ${errors == 1 ? 'error' : 'errors'}, '
    '$warnings ${warnings == 1 ? 'warning' : 'warnings'}',
  );
  return errors == 0 ? exitOk : exitFailed;
}

/// The ledger's disagreements with [dataset]: reviews of unknown items, and
/// `verified` items whose latest review does not verify them at their
/// `last_verified_at`.
Iterable<String> ledgerProblems(
  CurriculumDataset dataset,
  ReviewLedger ledger,
) sync* {
  final items = {for (final item in dataset.knowledgeItems) item.id};
  for (final review in ledger.reviews) {
    if (!items.contains(review.itemId)) {
      yield '${review.location}: error: a review of unknown item '
          '${review.itemId} [ledger]';
    }
  }
  for (final item in dataset.knowledgeItems) {
    if (item.verificationStatus != 'verified') continue;
    final at = dataset.locate((section: 'knowledge_items', key: item.id));
    final latest = ledger.latestFor(item.id);
    if (latest == null) {
      yield '$at: error: ${item.id} is verified, but the ledger has no '
          'review of it [ledger]';
    } else if (latest.outcome != ReviewOutcome.verified) {
      yield '$at: error: ${item.id} is verified, but its latest review, at '
          '${latest.location}, disputes it [ledger]';
    } else if (latest.reviewedAt != item.lastVerifiedAt) {
      yield '$at: error: ${item.id} was last verified at '
          '${item.lastVerifiedAt.toIso8601String()}, but its latest review, '
          'at ${latest.location}, is from '
          '${latest.reviewedAt.toIso8601String()} [ledger]';
    }
  }
}

/// `report`: ingests the dataset into an in-memory database and prints what
/// the release holds, file by file, and what ingestion generated for the
/// release date: the questions by format, the pairs skipped and why, the
/// items no multiple-choice question tests, and each track's coverage.
Future<int> report(List<String> args, StringSink out) async {
  const usage = 'dart run tool/curriculum/report.dart [--dataset <manifest>]';
  final options = ToolOptions.parse(args, named: {'dataset'});
  if (options == null) return printUsage(out, usage, args);
  final manifest = options['dataset'] ?? curriculumAssetPath;

  final CurriculumDataset dataset;
  try {
    dataset = readDataset(manifest);
  } on DatasetFormatException catch (error) {
    out.writeln('error: ${error.message}');
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

  final on = releaseDate(dataset);
  out
    ..writeln('Curriculum release ${dataset.version}')
    ..writeln(
      '  published ${dataset.publishedAt.toIso8601String()}; questions and '
      'coverage below are for $on (COV-5)',
    )
    ..writeln('  ${dataset.checksum}')
    ..writeln()
    ..writeln('Files');
  final counts = <String, Map<String, int>>{};
  for (final MapEntry(key: section, value: rows) in dataset.locations.entries) {
    for (final at in rows.values) {
      final perFile = counts.putIfAbsent(at.path, () => {});
      perFile[section] = (perFile[section] ?? 0) + 1;
    }
  }
  for (final file in dataset.files) {
    final perFile = counts[file] ?? const {};
    final parts = [
      for (final section in datasetSections.keys)
        if (perFile[section] case final n?)
          '$n ${n == 1 ? _labels[section]!.$1 : _labels[section]!.$2}',
    ];
    out.writeln('  $file: ${parts.isEmpty ? 'manifest' : parts.join(', ')}');
  }

  final db = AppDatabase(NativeDatabase.memory());
  try {
    final GenerationReport generated;
    try {
      generated = await CurriculumIngester(
        db,
        clock: clockOn(on),
      ).ingest(dataset);
    } on Exception catch (error) {
      out.writeln('error: the release does not ingest: $error');
      return exitFailed;
    }
    out
      ..writeln()
      ..writeln(
        'Questions: ${generated.questions} '
        '(${generated.flashcards} flashcards, '
        '${generated.multipleChoice} multiple choice)',
      );
    final byReason = <SkipReason, List<SkippedQuestion>>{};
    for (final skip in generated.skipped) {
      byReason.putIfAbsent(skip.reason, () => []).add(skip);
    }
    out.writeln('Skipped: ${generated.skipped.length}');
    for (final MapEntry(key: reason, value: skips) in byReason.entries) {
      out.writeln('  ${reason.name} (${skips.length}):');
      for (final skip in skips) {
        out.writeln('    ${skip.itemId} × ${skip.templateId}');
      }
    }
    final noMcq = await db.customSelect('''
      SELECT id, mcq_disabled FROM knowledge_items i
      WHERE NOT EXISTS (
        SELECT 1 FROM questions q
        JOIN question_templates t ON t.id = q.question_template_id
        WHERE q.knowledge_item_id = i.id AND t.mode = 'mcq')
      ORDER BY id''').get();
    out.writeln('Items with no multiple-choice question: ${noMcq.length}');
    for (final row in noMcq) {
      out.writeln(
        '  ${row.read<String>('id')}'
        '${row.read<bool>('mcq_disabled') ? ' (mcq_disabled)' : ''}',
      );
    }
    await _coverageSummary(
      out,
      db,
      manifest,
      on: on,
      skipped: generated.skipped,
    );
  } finally {
    await db.close();
  }

  out
    ..writeln()
    ..writeln('Warnings: ${validation.warnings.length}');
  for (final warning in validation.warnings) {
    out.writeln('  $warning');
  }
  return exitOk;
}

/// The coverage section of `report`: each selectable track's main metrics
/// and blocking gaps, from the ingested [db], when the release has a
/// coverage policy.
Future<void> _coverageSummary(
  StringSink out,
  AppDatabase db,
  String manifest, {
  required String on,
  required List<SkippedQuestion> skipped,
}) async {
  final policyPath = coveragePolicyPath(manifest);
  out.writeln();
  try {
    final policy = readCoveragePolicy(policyPath);
    if (policy == null) {
      out.writeln('Coverage: no policy at $policyPath');
      return;
    }
    final baselinePath = coverageBaselinePath(manifest);
    final baselineFile = File(baselinePath);
    final baseline = baselineFile.existsSync()
        ? CoverageBaseline.parse(
            baselineFile.readAsStringSync(),
            path: baselinePath,
          )
        : null;
    out.writeln(
      'Coverage on $on (dart run tool/coverage_report.dart for the matrix)',
    );
    final checker = CoverageChecker(db, policy);
    for (final track in await checker.selectableTracks()) {
      final coverage = await checker.check(track.id, on: on, skipped: skipped);
      int count(CoverageMetric metric) => coverage.counts[metric];
      final blocking = coverage.blockingGaps.toList();
      final known = blocking
          .where(
            (gap) => baseline?.knownGaps.any((k) => k.matches(gap)) ?? false,
          )
          .length;
      out.writeln(
        '  ${track.id}: ${count(CoverageMetric.items)} items '
        '(${count(CoverageMetric.core)} core), '
        '${count(CoverageMetric.testable)} testable, '
        '${count(CoverageMetric.flashcardOnly)} flashcard-only, '
        '${count(CoverageMetric.usefulPractice)} with useful practice; '
        '${blocking.length} blocking gaps, $known known',
      );
    }
  } on CoveragePolicyException catch (error) {
    out.writeln('Coverage: the policy does not fit the release:');
    for (final problem in error.problems) {
      out.writeln('  $problem');
    }
  } on CoverageBaselineException catch (error) {
    out.writeln('Coverage: ${error.message}');
  }
}

/// `verify`: records an expert's review of an item. It appends the review
/// to the item's ledger file and sets the item's `verification_status` in its
/// area file, so the change is an ordinary content change, reviewed and
/// versioned like any other (D3). A `verified` review also sets
/// `last_verified_at`; a dispute leaves it at the last check that confirmed
/// the item.
Future<int> verify(
  List<String> args,
  StringSink out, {
  Clock clock = const Clock(),
}) async {
  const usage =
      'dart run tool/curriculum/verify.dart <item-id> --reviewer <name> '
      '--outcome verified|disputed [--notes <text>] [--at <UTC instant>] '
      '[--dataset <manifest>]\n'
      '  A disputed review needs --notes saying what is wrong.';
  final options = ToolOptions.parse(
    args,
    named: {'dataset', 'reviewer', 'outcome', 'notes', 'at'},
    positional: 1,
  );
  final outcome = ReviewOutcome.values.asNameMap()[options?['outcome']];
  final reviewer = options?['reviewer']?.trim() ?? '';
  final notes = options?['notes']?.trim();
  if (options == null ||
      outcome == null ||
      reviewer.isEmpty ||
      (outcome == ReviewOutcome.disputed && (notes == null || notes.isEmpty))) {
    return printUsage(out, usage, args);
  }
  final manifest = options['dataset'] ?? curriculumAssetPath;
  final itemId = options.positional.single;

  final DateTime at;
  final instant = options['at'];
  if (instant == null) {
    at = utcNow(clock);
  } else if (RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')
      .hasMatch(instant)) {
    at = DateTime.parse(instant);
  } else {
    out.writeln(
      'error: --at "$instant" is not a UTC instant with milliseconds',
    );
    return exitUsage;
  }

  final CurriculumDataset dataset;
  try {
    dataset = readDataset(manifest);
  } on DatasetFormatException catch (error) {
    out.writeln('error: ${error.message}');
    return exitFailed;
  }
  final location = dataset.locate((section: 'knowledge_items', key: itemId));
  if (location == null) {
    out.writeln(
      'error: there is no item $itemId in release ${dataset.version}',
    );
    return exitFailed;
  }

  final verified = outcome == ReviewOutcome.verified;
  final status = verified ? 'verified' : 'unverified';
  final area = File(location.path);
  final original = area.readAsStringSync();
  final edited = setItemVerification(
    original,
    itemId,
    status: status,
    verifiedAt: verified ? at : null,
  );
  final review = Review(
    itemId: itemId,
    reviewer: reviewer,
    reviewedAt: at,
    outcome: outcome,
    notes: notes,
  );
  final areaName = location.path.split('/').last;
  final ledgerPath = '${ledgerFolder(manifest)}/$areaName';
  final ledger = File(ledgerPath);
  final String ledgerText;
  try {
    ledgerText = appendReview(
      ledger.existsSync() ? ledger.readAsStringSync() : null,
      review,
      path: ledgerPath,
      area: location.path,
    );
  } on LedgerFormatException catch (error) {
    out.writeln('error: ${error.message}');
    return exitFailed;
  }

  // The edited release must still parse and validate before anything is
  // written.
  final files = [
    for (final path in dataset.files)
      DatasetFile(
        path,
        path == location.path ? edited : File(path).readAsStringSync(),
      ),
  ];
  final List<ValidationIssue> errors;
  try {
    errors = validateDataset(CurriculumDataset.fromFiles(files)).errors;
  } on DatasetFormatException catch (error) {
    out.writeln('error: the edited release does not parse: ${error.message}');
    return exitFailed;
  }
  if (errors.isNotEmpty) {
    out.writeln('error: the edited release does not validate:');
    for (final issue in errors) {
      out.writeln('  $issue');
    }
    return exitFailed;
  }
  ledger
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(ledgerText);
  out.writeln(
    'Recorded a ${outcome.name} review of $itemId by $reviewer, at '
    '${at.toIso8601String()}, in $ledgerPath.',
  );
  if (edited == original) {
    out.writeln('$itemId stays $status, so the release is unchanged.');
    return exitOk;
  }
  area.writeAsStringSync(edited);
  out
    ..writeln(
      verified
          ? 'Set its verification_status to verified and its '
                'last_verified_at in $location.'
          : 'Set its verification_status to unverified in $location.',
    )
    ..writeln(
      'Give the release a new dataset_version in $manifest before you commit.',
    );
  return exitOk;
}

/// [text], an area file, with item [itemId]'s `verification_status` set to
/// [status] and, when [verifiedAt] is given, its `last_verified_at` to it.
/// Everything else is kept as written: comments, order, quoting and line
/// endings.
String setItemVerification(
  String text,
  String itemId, {
  required String status,
  DateTime? verifiedAt,
}) {
  final document = loadYamlNode(text);
  final items = document is YamlMap ? document.nodes['knowledge_items'] : null;
  if (items is! YamlList) {
    throw ArgumentError('the file has no knowledge_items section');
  }
  final row = items.nodes.whereType<YamlMap>().firstWhere(
    (row) => row['id'] == itemId,
    orElse: () => throw ArgumentError.value(itemId, 'itemId', 'not in file'),
  );
  final lastVerified = row.nodes['last_verified_at']!;
  final edits = <(int, int, String)>[
    if (verifiedAt != null)
      (
        lastVerified.span.start.offset,
        lastVerified.span.end.offset,
        '"${verifiedAt.toIso8601String()}"',
      ),
  ];
  final current = row.nodes['verification_status'];
  // An omitted status is the schema default, unverified.
  if ((current?.value ?? 'unverified') != status) {
    if (current != null) {
      edits.add((current.span.start.offset, current.span.end.offset, status));
    } else if (row.style == CollectionStyle.FLOW) {
      // After the row's last value, inside its braces.
      final end = row.nodes.values
          .map((value) => value.span.end.offset)
          .reduce((a, b) => a > b ? a : b);
      edits.add((end, end, ', verification_status: $status'));
    } else {
      // A new line after last_verified_at's, at its key's indent.
      final key = row.nodes.keys.cast<YamlNode>().firstWhere(
        (key) => key.value == 'last_verified_at',
      );
      final newline = text.contains('\r\n') ? '\r\n' : '\n';
      final lineEnd = text.indexOf('\n', lastVerified.span.end.offset);
      final at = lineEnd < 0 ? text.length : lineEnd + 1;
      final prefix = lineEnd < 0 ? newline : '';
      edits.add((
        at,
        at,
        '$prefix${' ' * key.span.start.column}verification_status: '
            '$status$newline',
      ));
    }
  }
  edits.sort((a, b) => b.$1.compareTo(a.$1));
  var result = text;
  for (final (start, end, replacement) in edits) {
    result = result.replaceRange(start, end, replacement);
  }
  return result;
}

/// The ledger file at [path], [existing] or a new one for [area], with
/// [review] appended. A review may not be older than the one before it.
String appendReview(
  String? existing,
  Review review, {
  required String path,
  required String area,
}) {
  if (existing == null) {
    return '# Expert reviews of the items in $area, oldest first.\n'
        '# Recorded with tool/curriculum/verify.dart; never edit or remove\n'
        '# one (decision D3).\n'
        '\n'
        'reviews:\n'
        '${review.toYaml()}';
  }
  final ledger = ReviewLedger.parse(path, existing);
  if (ledger.reviews.isNotEmpty &&
      review.reviewedAt.isBefore(ledger.reviews.last.reviewedAt)) {
    throw LedgerFormatException(
      '$path: reviews are appended in time order; this one is older than '
      'the last one, at ${ledger.reviews.last.location}',
    );
  }
  final newline = existing.contains('\r\n') ? '\r\n' : '\n';
  var text = existing.replaceFirst(
    RegExp(r'^reviews:[ \t]*\[\][ \t]*$', multiLine: true),
    'reviews:',
  );
  if (!text.endsWith('\n')) text += newline;
  return text + review.toYaml().replaceAll('\n', newline);
}

/// Prints [usage]: success when it was asked for with `--help`, a usage
/// error otherwise.
int printUsage(StringSink out, String usage, List<String> args) {
  out.writeln('usage: $usage');
  return args.contains('--help') || args.contains('-h') ? exitOk : exitUsage;
}

/// Each section's rows, counted: one, and more.
const _labels = {
  'curriculum_domains': ('domain', 'domains'),
  'tasting_grids': ('tasting grid', 'tasting grids'),
  'certifications': ('track', 'tracks'),
  'node_types': ('node type', 'node types'),
  'relation_types': ('relation type', 'relation types'),
  'relation_type_signatures': ('relation signature', 'relation signatures'),
  'knowledge_nodes': ('node', 'nodes'),
  'quantity_values': ('quantity', 'quantities'),
  'node_alternative_names': ('alternative name', 'alternative names'),
  'knowledge_relations': ('relation', 'relations'),
  'knowledge_items': ('item', 'items'),
  'knowledge_item_prerequisites': ('prerequisite', 'prerequisites'),
  'certification_knowledge_mappings': ('track mapping', 'track mappings'),
  'source_citations': ('source', 'sources'),
  'knowledge_item_citations': ('item citation', 'item citations'),
  'question_templates': ('question template', 'question templates'),
  'tasting_grid_attributes': ('grid attribute', 'grid attributes'),
  'tasting_grid_values': ('grid value', 'grid values'),
  'relation_set_assertions': (
    'completeness assertion',
    'completeness assertions',
  ),
  'map_layers': ('map layer', 'map layers'),
  'map_layer_citations': ('layer source', 'layer sources'),
  'node_geometries': ('node geometry', 'node geometries'),
};

/// Command-line options: `--name value` or `--name=value`, `--flag`, and
/// positional arguments.
final class ToolOptions {
  ToolOptions(this.named, this.flags, this.positional);

  /// The options in [args], or null when they do not fit: an unknown name, a
  /// missing value, the wrong number of positional arguments, or `--help`.
  /// [flags] take no value.
  static ToolOptions? parse(
    List<String> args, {
    required Set<String> named,
    Set<String> flags = const {},
    int positional = 0,
  }) {
    final values = <String, String>{};
    final set = <String>{};
    final rest = <String>[];
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--help' || arg == '-h') return null;
      if (!arg.startsWith('--')) {
        rest.add(arg);
        continue;
      }
      final equals = arg.indexOf('=');
      final name = arg.substring(2, equals < 0 ? arg.length : equals);
      if (flags.contains(name) && equals < 0) {
        set.add(name);
      } else if (!named.contains(name)) {
        return null;
      } else if (equals >= 0) {
        values[name] = arg.substring(equals + 1);
      } else if (i + 1 < args.length) {
        values[name] = args[++i];
      } else {
        return null;
      }
    }
    if (rest.length != positional) return null;
    return ToolOptions(values, set, rest);
  }

  final Map<String, String> named;
  final Set<String> flags;
  final List<String> positional;

  String? operator [](String name) => named[name];

  bool has(String flag) => flags.contains(flag);
}
