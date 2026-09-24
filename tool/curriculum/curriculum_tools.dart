import 'dart:io';

import 'package:clock/clock.dart';
import 'package:drift/native.dart';
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

/// Exit codes: success, problems found, and a usage error.
const exitOk = 0, exitFailed = 1, exitUsage = 64;

/// Reads the dataset whose manifest is at [manifest] from disk.
CurriculumDataset readDataset(String manifest) => CurriculumDataset.loadSync(
  manifest,
  (path) => File(path).readAsStringSync(),
);

/// The review ledger's folder: `reviews/` next to [manifest].
String ledgerFolder(String manifest) {
  final path = manifest.replaceAll(r'\', '/');
  final slash = path.lastIndexOf('/');
  return slash < 0 ? 'reviews' : '${path.substring(0, slash)}/reviews';
}

/// `lint`: prints every problem of the dataset as `file:line: kind: message
/// [rule]`: format errors, the validator's errors and warnings, and ledger
/// errors. Fails if there is any error.
Future<int> lint(List<String> args, StringSink out) async {
  const usage = 'dart run tool/curriculum/lint.dart [--dataset <manifest>]';
  final options = _Options.parse(args, named: {'dataset'});
  if (options == null) return _usage(out, usage, args);
  final manifest = options['dataset'] ?? curriculumAssetPath;

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
/// the release holds, file by file, and what ingestion generated: the
/// questions by format, the pairs skipped and why, and the items no
/// multiple-choice question tests.
Future<int> report(
  List<String> args,
  StringSink out, {
  Clock clock = const Clock(),
}) async {
  const usage = 'dart run tool/curriculum/report.dart [--dataset <manifest>]';
  final options = _Options.parse(args, named: {'dataset'});
  if (options == null) return _usage(out, usage, args);
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

  out
    ..writeln('Curriculum release ${dataset.version}')
    ..writeln('  published ${dataset.publishedAt.toIso8601String()}')
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
    final generated = await CurriculumIngester(
      db,
      clock: clock,
    ).ingest(dataset);
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
  final options = _Options.parse(
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
    return _usage(out, usage, args);
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
int _usage(StringSink out, String usage, List<String> args) {
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
};

/// Command-line options: `--name value` or `--name=value`, and positional
/// arguments.
final class _Options {
  _Options(this.named, this.positional);

  /// The options in [args], or null when they do not fit: an unknown name, a
  /// missing value, the wrong number of positional arguments, or `--help`.
  static _Options? parse(
    List<String> args, {
    required Set<String> named,
    int positional = 0,
  }) {
    final values = <String, String>{};
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
      if (!named.contains(name)) return null;
      if (equals >= 0) {
        values[name] = arg.substring(equals + 1);
      } else if (i + 1 < args.length) {
        values[name] = args[++i];
      } else {
        return null;
      }
    }
    if (rest.length != positional) return null;
    return _Options(values, rest);
  }

  final Map<String, String> named;
  final List<String> positional;

  String? operator [](String name) => named[name];
}
