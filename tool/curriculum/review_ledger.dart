import 'dart:convert';
import 'dart:io';

import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:yaml/yaml.dart';

/// What an expert concluded about an item (decision D3).
enum ReviewOutcome {
  /// The item matches its cited source: it becomes `verified`.
  verified,

  /// The reviewer found a problem, described in the notes: the item stays or
  /// becomes `unverified` until it is fixed and reviewed again.
  disputed,
}

/// Thrown when a ledger file does not follow the ledger format.
class LedgerFormatException implements Exception {
  LedgerFormatException(this.message);

  final String message;

  @override
  String toString() => 'Invalid review ledger: $message';
}

/// One expert review of a knowledge item.
final class Review {
  const Review({
    required this.itemId,
    required this.reviewer,
    required this.reviewedAt,
    required this.outcome,
    this.notes,
    this.location,
  });

  final String itemId;

  /// Who reviewed the item, with the qualification that makes them a
  /// qualified reviewer (D3).
  final String reviewer;

  /// A UTC instant with whole milliseconds. A `verified` review sets the
  /// item's `last_verified_at` to it.
  final DateTime reviewedAt;

  final ReviewOutcome outcome;
  final String? notes;

  /// Where the review is written, when it was read from a file.
  final DatasetLocation? location;

  /// The review as a ledger entry, indented as a list item under `reviews:`.
  String toYaml() {
    final lines = [
      '  - knowledge_item_id: $itemId',
      '    reviewer: ${jsonEncode(reviewer)}',
      '    reviewed_at: "${reviewedAt.toIso8601String()}"',
      '    outcome: ${outcome.name}',
      if (notes case final notes?) '    notes: ${jsonEncode(notes)}',
    ];
    return '${lines.join('\n')}\n';
  }
}

/// The review ledger: `reviews/` next to the dataset's manifest, one file per
/// area file (`reviews/france.yaml` for `areas/france.yaml`). Each lists the
/// reviews of that area's items, oldest first, and is only ever appended to,
/// so every change to an item's verification status is auditable (D3). The
/// app does not bundle it.
final class ReviewLedger {
  const ReviewLedger(this.reviews);

  /// Parses one ledger file: a `reviews` list, each entry with
  /// `knowledge_item_id`, `reviewer`, `reviewed_at`, `outcome` and optional
  /// `notes`, in time order.
  factory ReviewLedger.parse(String path, String text) {
    final Object? document;
    try {
      document = loadYamlNode(text, sourceUrl: Uri.file(path));
    } on YamlException catch (error) {
      final line = error.span?.start.line;
      throw LedgerFormatException(
        '$path${line == null ? '' : ':${line + 1}'}: not valid YAML: '
        '${error.message}',
      );
    }
    if (document is! YamlMap ||
        document.keys.any((key) => key != 'reviews') ||
        document.nodes['reviews'] is! YamlList) {
      throw LedgerFormatException(
        '$path: a ledger file holds one "reviews" list',
      );
    }
    final reviews = <Review>[];
    for (final node in (document.nodes['reviews']! as YamlList).nodes) {
      final at = DatasetLocation(path, node.span.start.line + 1);
      if (node is! YamlMap) {
        throw LedgerFormatException('$at: a review must be a mapping');
      }
      final unknown = node.keys.where((key) => !_columns.contains(key));
      if (unknown.isNotEmpty) {
        throw LedgerFormatException('$at: unknown keys ${unknown.join(', ')}');
      }
      String text(String key) {
        final value = node[key];
        if (value is! String || value.trim().isEmpty) {
          throw LedgerFormatException('$at: $key must be text');
        }
        return value;
      }

      final instant = text('reviewed_at');
      if (!_utcMilliseconds.hasMatch(instant)) {
        throw LedgerFormatException(
          '$at: reviewed_at "$instant" is not a UTC instant with milliseconds',
        );
      }
      final outcome = ReviewOutcome.values.asNameMap()[node['outcome']];
      if (outcome == null) {
        throw LedgerFormatException(
          '$at: outcome must be one of '
          '${ReviewOutcome.values.map((o) => o.name).join(', ')}',
        );
      }
      final review = Review(
        itemId: text('knowledge_item_id'),
        reviewer: text('reviewer'),
        reviewedAt: DateTime.parse(instant),
        outcome: outcome,
        notes: node['notes'] == null ? null : text('notes'),
        location: at,
      );
      if (reviews.isNotEmpty &&
          review.reviewedAt.isBefore(reviews.last.reviewedAt)) {
        throw LedgerFormatException(
          '$at: reviews are appended in time order; this one is older than '
          'the review before it',
        );
      }
      reviews.add(review);
    }
    return ReviewLedger(reviews);
  }

  /// Reads every `*.yaml` file in [folder], in name order. A missing folder
  /// is an empty ledger.
  factory ReviewLedger.read(String folder) {
    final directory = Directory(folder);
    if (!directory.existsSync()) return const ReviewLedger([]);
    final files =
        directory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.yaml'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    return ReviewLedger([
      for (final file in files)
        ...ReviewLedger.parse(
          file.path.replaceAll(r'\', '/'),
          file.readAsStringSync(),
        ).reviews,
    ]);
  }

  static const _columns = {
    'knowledge_item_id',
    'reviewer',
    'reviewed_at',
    'outcome',
    'notes',
  };

  static final _utcMilliseconds = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
  );

  final List<Review> reviews;

  /// The latest review of [itemId], if it was ever reviewed.
  Review? latestFor(String itemId) {
    Review? latest;
    for (final review in reviews) {
      if (review.itemId != itemId) continue;
      if (latest == null || !review.reviewedAt.isBefore(latest.reviewedAt)) {
        latest = review;
      }
    }
    return latest;
  }
}
