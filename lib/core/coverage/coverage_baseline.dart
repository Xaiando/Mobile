import 'dart:convert';

import 'coverage_model.dart';

/// Thrown when a coverage baseline cannot be read, or cannot be raised.
class CoverageBaselineException implements Exception {
  CoverageBaselineException(this.message);

  final String message;

  @override
  String toString() => 'Coverage baseline: $message';
}

/// A blocking gap the build accepts until a task closes it (backlog F1).
///
/// It holds on every track that maps the item: an item without a question,
/// or served only flashcards, is so whatever the track's depth.
final class KnownGap {
  const KnownGap({
    required this.item,
    required this.kind,
    required this.reason,
    required this.closedBy,
  });

  final String item;
  final GapKind kind;

  /// Why the gap is accepted for now.
  final String reason;

  /// The backlog task that will close it, e.g. `Q1`.
  final String closedBy;

  bool matches(CoverageGap gap) => item == gap.itemId && kind == gap.kind;

  @override
  String toString() => '$item ${kind.key}';
}

/// A group's metrics as the baseline records them.
typedef BaselineCounts = Map<CoverageMetric, int>;

/// One domain of a track in the baseline: its metrics, whole and by area.
final class BaselineDomain {
  const BaselineDomain({required this.counts, required this.areas});

  final BaselineCounts counts;

  /// By area ID.
  final Map<String, BaselineCounts> areas;
}

/// One track in the baseline.
final class BaselineTrack {
  const BaselineTrack({required this.counts, required this.domains});

  final BaselineCounts counts;

  /// By domain ID.
  final Map<String, BaselineDomain> domains;
}

/// What a comparison with the baseline found. The build fails on any
/// failure; notices say what could be raised or removed.
final class RatchetResult {
  const RatchetResult(this.failures, this.notices);

  final List<String> failures;
  final List<String> notices;

  bool get passes => failures.isEmpty;
}

/// The committed coverage baseline, `coverage_baseline.json`: the metrics of
/// every selectable track, by domain and area, and the known blocking gaps
/// (audit COV-3).
///
/// The build fails when a metric that should only rise falls below it, or
/// when a blocking gap is not known. `tool/coverage_report.dart
/// --update-baseline` rewrites the metrics; the known gaps are edited by
/// hand, each with its reason and the task that closes it.
final class CoverageBaseline {
  const CoverageBaseline({
    required this.release,
    required this.on,
    required this.tracks,
    this.knownGaps = const [],
  });

  /// The metrics of [coverage], with [knownGaps].
  factory CoverageBaseline.of(
    Iterable<TrackCoverage> coverage, {
    required String release,
    List<KnownGap> knownGaps = const [],
  }) {
    final tracks = coverage.toList();
    return CoverageBaseline(
      release: release,
      on: tracks.isEmpty ? null : tracks.first.on,
      tracks: {
        for (final track in tracks)
          track.trackId: BaselineTrack(
            counts: track.counts.toMap(),
            domains: {
              for (final domain in track.domains)
                domain.id: BaselineDomain(
                  counts: domain.counts.toMap(),
                  areas: {
                    for (final MapEntry(key: area, value: counts)
                        in domain.areas.entries)
                      area.id: counts.toMap(),
                  },
                ),
            },
          ),
      },
      knownGaps: knownGaps,
    );
  }

  /// Parses a baseline written by [toJson], or edited by hand.
  factory CoverageBaseline.parse(
    String text, {
    String path = 'coverage_baseline.json',
  }) {
    Never fail(String message) =>
        throw CoverageBaselineException('$path: $message');

    final Object? document;
    try {
      document = jsonDecode(text);
    } on FormatException catch (error) {
      fail('not valid JSON: ${error.message}');
    }
    Map<String, Object?> mapping(Object? value, String where) =>
        value is Map<String, Object?>
        ? value
        : fail('$where must be an object');

    BaselineCounts counts(Object? value, String where) => {
      for (final MapEntry(:key, :value) in mapping(value, where).entries)
        (CoverageMetric.byKey(key) ??
            fail('$where: unknown metric "$key"')): value is int && value >= 0
            ? value
            : fail('$where.$key must be a count'),
    };

    String field(Map<String, Object?> gap, String key, String where) =>
        switch (gap[key]) {
          final String value when value.trim().isNotEmpty => value.trim(),
          _ => fail('$where needs a "$key"'),
        };

    final root = mapping(document, 'the baseline');
    const keys = {'about', 'release', 'on', 'tracks', 'known_gaps'};
    for (final key in root.keys) {
      if (!keys.contains(key)) fail('unknown key "$key"');
    }
    final knownGaps = <KnownGap>[];
    final gaps = root['known_gaps'] ?? const <Object?>[];
    if (gaps is! List<Object?>) fail('known_gaps must be a list');
    for (final (index, value) in gaps.indexed) {
      final where = 'known_gaps[$index]';
      final gap = mapping(value, where);
      for (final key in gap.keys) {
        if (!const {'item', 'gap', 'reason', 'closed_by'}.contains(key)) {
          fail('$where: unknown key "$key"');
        }
      }
      final kind = GapKind.byKey(field(gap, 'gap', where));
      if (kind == null || !kind.isBlocking) {
        fail(
          '$where: gap must be one of '
          '${[for (final k in GapKind.values)
            if (k.isBlocking) k.key].join(', ')}',
        );
      }
      final known = KnownGap(
        item: field(gap, 'item', where),
        kind: kind,
        reason: field(gap, 'reason', where),
        closedBy: field(gap, 'closed_by', where),
      );
      if (knownGaps.any((k) => '$k' == '$known')) {
        fail('$where: $known is listed twice');
      }
      knownGaps.add(known);
    }
    return CoverageBaseline(
      release: root['release'] is String ? root['release'] as String : null,
      on: root['on'] is String ? root['on'] as String : null,
      tracks: {
        for (final MapEntry(key: id, value: track) in mapping(
          root['tracks'] ?? const <String, Object?>{},
          'tracks',
        ).entries)
          id: BaselineTrack(
            counts: counts(mapping(track, id)['total'], '$id.total'),
            domains: {
              for (final MapEntry(key: domainId, value: domain) in mapping(
                mapping(track, id)['domains'] ?? const <String, Object?>{},
                '$id.domains',
              ).entries)
                domainId: BaselineDomain(
                  counts: counts(
                    mapping(domain, '$id.$domainId')['total'],
                    '$id.$domainId.total',
                  ),
                  areas: {
                    for (final MapEntry(key: areaId, value: area) in mapping(
                      mapping(domain, '$id.$domainId')['areas'] ??
                          const <String, Object?>{},
                      '$id.$domainId.areas',
                    ).entries)
                      areaId: counts(area, '$id.$domainId.$areaId'),
                  },
                ),
            },
          ),
      },
      knownGaps: knownGaps,
    );
  }

  /// The release the metrics were taken from.
  final String? release;

  /// The date the curriculum was measured on.
  final String? on;

  /// By track ID.
  final Map<String, BaselineTrack> tracks;
  final List<KnownGap> knownGaps;

  /// Compares [coverage] with the baseline: the ratchet of audit COV-3.
  ///
  /// It fails when a metric that should only rise falls below the baseline,
  /// when a blocking gap is not known, or when a track has no baseline.
  /// [allTracks] says [coverage] holds every selectable track: a track
  /// missing from it is no longer selectable, and a known gap found on none
  /// of them is closed.
  RatchetResult check(
    Iterable<TrackCoverage> coverage, {
    bool allTracks = true,
  }) {
    final failures = <String>[];
    final notices = <String>[];
    final checked = <String>{};
    final gaps = <String>{};
    for (final track in coverage) {
      checked.add(track.trackId);
      final baseline = tracks[track.trackId];
      if (baseline == null) {
        failures.add(
          '${track.trackId} has no baseline: record it with '
          '--update-baseline',
        );
        continue;
      }
      var rose = false;
      void compare(String where, BaselineCounts before, BaselineCounts now) {
        for (final MapEntry(key: metric, value: was) in before.entries) {
          if (!metric.higherIsBetter) continue;
          final value = now[metric] ?? 0;
          if (value < was) {
            failures.add('$where: ${metric.key} fell from $was to $value');
          } else if (value > was) {
            rose = true;
          }
        }
      }

      compare(track.trackId, baseline.counts, track.counts.toMap());
      final domains = {for (final d in track.domains) d.id: d};
      for (final MapEntry(key: domainId, value: before)
          in baseline.domains.entries) {
        final domain = domains[domainId];
        final where = '${track.trackId} > ${domain?.name ?? domainId}';
        compare(where, before.counts, domain?.counts.toMap() ?? const {});
        final areas = {
          for (final MapEntry(key: area, value: counts)
              in domain?.areas.entries ??
                  <MapEntry<CoverageArea, CoverageCounts>>[])
            area.id: (area, counts),
        };
        for (final MapEntry(key: areaId, value: counts)
            in before.areas.entries) {
          final now = areas[areaId];
          compare(
            '$where > ${now?.$1.name ?? areaId}',
            counts,
            now?.$2.toMap() ?? const {},
          );
        }
      }
      if (rose) {
        notices.add(
          '${track.trackId}: coverage rose; raise the baseline with '
          '--update-baseline',
        );
      }

      for (final gap in track.blockingGaps) {
        if (!knownGaps.any((known) => known.matches(gap))) {
          failures.add(
            '${track.trackId}: new gap: $gap. Close it, or list it in '
            'known_gaps with a reason and the task that closes it',
          );
        }
        gaps.add('${gap.itemId} ${gap.kind.key}');
      }
    }
    if (allTracks) {
      for (final id in tracks.keys) {
        if (!checked.contains(id)) {
          notices.add(
            '$id is not a selectable track any more; --update-baseline '
            'drops it',
          );
        }
      }
      for (final known in knownGaps) {
        if (!gaps.contains('$known')) {
          notices.add(
            'closed: $known (${known.closedBy}); remove it from known_gaps, '
            'as --update-baseline does',
          );
        }
      }
    }
    return RatchetResult(failures, notices);
  }

  /// A baseline at [coverage]'s metrics, for release [release], keeping the
  /// known gaps that are still open.
  ///
  /// Throws a [CoverageBaselineException] naming every blocking gap that is
  /// not known: each needs a reason and a task before it is accepted.
  CoverageBaseline raisedTo(
    Iterable<TrackCoverage> coverage, {
    required String release,
  }) {
    final tracks = coverage.toList();
    final open = [for (final track in tracks) ...track.blockingGaps];
    final unknown = {
      for (final gap in open)
        if (!knownGaps.any((known) => known.matches(gap))) '$gap',
    };
    if (unknown.isNotEmpty) {
      throw CoverageBaselineException(
        'these gaps are not in known_gaps; close them, or add each with a '
        'reason and the task that closes it:\n  ${unknown.join('\n  ')}',
      );
    }
    return CoverageBaseline.of(
      tracks,
      release: release,
      knownGaps: [
        for (final known in knownGaps)
          if (open.any(known.matches)) known,
      ],
    );
  }

  /// The baseline as JSON: one line per group's metrics, so a change to
  /// the numbers reads well in a diff.
  String toJson() {
    final out = StringBuffer();
    String counts(BaselineCounts values) => jsonEncode({
      for (final metric in CoverageMetric.values) metric.key: ?values[metric],
    }).replaceAll(',', ', ').replaceAll(':', ': ');

    void entries<T>(
      Map<String, T> map,
      int indent,
      void Function(String key, T value, String pad) write,
    ) {
      final pad = ' ' * indent;
      final keys = map.keys.toList()..sort();
      for (final (i, key) in keys.indexed) {
        write(key, map[key] as T, pad);
        out.writeln(i < keys.length - 1 ? ',' : '');
      }
    }

    out
      ..writeln('{')
      ..writeln(
        '  "about": ${jsonEncode('Question coverage baseline (backlog F1, audit COV-3). The build '
        'fails when a metric falls below it or a blocking gap is not in '
        'known_gaps. Regenerate the metrics with dart run '
        'tool/coverage_report.dart --update-baseline; edit known_gaps by '
        'hand.')},',
      )
      ..writeln('  "release": ${jsonEncode(release)},')
      ..writeln('  "on": ${jsonEncode(on)},')
      ..writeln('  "tracks": {');
    entries(tracks, 4, (id, track, pad) {
      out
        ..writeln('$pad${jsonEncode(id)}: {')
        ..writeln('$pad  "total": ${counts(track.counts)},')
        ..writeln('$pad  "domains": {');
      entries(track.domains, pad.length + 4, (domainId, domain, pad) {
        out
          ..writeln('$pad${jsonEncode(domainId)}: {')
          ..writeln('$pad  "total": ${counts(domain.counts)},')
          ..writeln('$pad  "areas": {');
        entries(domain.areas, pad.length + 4, (areaId, area, pad) {
          out.write('$pad${jsonEncode(areaId)}: ${counts(area)}');
        });
        out
          ..writeln('$pad  }')
          ..write('$pad}');
      });
      out
        ..writeln('$pad  }')
        ..write('$pad}');
    });
    out
      ..writeln('  },')
      ..write('  "known_gaps": [');
    final gaps = [...knownGaps]..sort((a, b) => '$a'.compareTo('$b'));
    if (gaps.isEmpty) {
      out.writeln(']');
    } else {
      out.writeln();
      for (final (i, gap) in gaps.indexed) {
        out
          ..writeln('    {')
          ..writeln('      "item": ${jsonEncode(gap.item)},')
          ..writeln('      "gap": ${jsonEncode(gap.kind.key)},')
          ..writeln('      "reason": ${jsonEncode(gap.reason)},')
          ..writeln('      "closed_by": ${jsonEncode(gap.closedBy)}')
          ..writeln(i < gaps.length - 1 ? '    },' : '    }');
      }
      out.writeln('  ]');
    }
    out.writeln('}');
    return out.toString();
  }
}
