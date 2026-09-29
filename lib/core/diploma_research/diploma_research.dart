import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';

import '../database/app_database.dart';
import '../database/uuid.dart';
import '../time/utc_clock.dart';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
const maxDiplomaResearchSnapshotCharacters = 240000;
const _maxSources = 40;
const _maxClaims = 40;

const researchChecks = <String, String>{
  'brief': 'Check the scope and presentation rules in my own brief',
  'sources': 'Appraise the relevance and limits of each source',
  'claims': 'Link main claims to evidence and consider counterevidence',
  'references': 'Check citations and reference list for consistency',
  'revision': 'Revise the argument and proofread the exported copy',
};

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) throw const FormatException('Invalid research record.');
  return Map<String, dynamic>.from(value);
}

String _text(Map<String, dynamic> row, String field, int max) {
  final value = row[field];
  if (value is! String || value.length > max) {
    throw FormatException('Invalid research $field.');
  }
  return value;
}

DateTime _instant(Object? value) {
  if (value is! String) throw const FormatException('Invalid research time.');
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    throw const FormatException('Research time must be canonical UTC.');
  }
  return parsed;
}

/// A learner-entered source. Empty fields are allowed while the log is drafted.
class ResearchSource {
  ResearchSource.fromJson(Map<String, dynamic> row)
    : id = _text(row, 'id', 36),
      citation = _text(row, 'citation', 1000),
      url = _text(row, 'url', 1200),
      date = _text(row, 'date', 80),
      scopeMethod = _text(row, 'scopeMethod', 2000),
      strength = _text(row, 'strength', 2000),
      limitation = _text(row, 'limitation', 2000) {
    if (!_uuid.hasMatch(id)) throw const FormatException('Invalid source ID.');
  }

  final String id;
  final String citation;
  final String url;
  final String date;
  final String scopeMethod;
  final String strength;
  final String limitation;

  Map<String, dynamic> toJson() => {
    'id': id,
    'citation': citation,
    'url': url,
    'date': date,
    'scopeMethod': scopeMethod,
    'strength': strength,
    'limitation': limitation,
  };

  bool get hasWork => [
    citation,
    url,
    date,
    scopeMethod,
    strength,
    limitation,
  ].any((value) => value.trim().isNotEmpty);
}

/// A claim explicitly tied to saved sources, with room for contrary evidence.
class ResearchClaim {
  ResearchClaim.fromJson(Map<String, dynamic> row)
    : id = _text(row, 'id', 36),
      statement = _text(row, 'statement', 2500),
      sourceIds = Set<String>.from(row['sourceIds'] as List),
      counterevidence = _text(row, 'counterevidence', 2500),
      conclusion = _text(row, 'conclusion', 2500) {
    if (!_uuid.hasMatch(id) ||
        (row['sourceIds'] as List).length != sourceIds.length ||
        sourceIds.any((sourceId) => !_uuid.hasMatch(sourceId))) {
      throw const FormatException('Invalid claim links.');
    }
  }

  final String id;
  final String statement;
  final Set<String> sourceIds;
  final String counterevidence;
  final String conclusion;

  Map<String, dynamic> toJson() => {
    'id': id,
    'statement': statement,
    'sourceIds': sourceIds.toList()..sort(),
    'counterevidence': counterevidence,
    'conclusion': conclusion,
  };

  bool get hasWork => [
    statement,
    counterevidence,
    conclusion,
  ].any((value) => value.trim().isNotEmpty);
}

/// Private formative work, never an assessed D6 submission or unit pass.
class DiplomaResearchWorkspace {
  DiplomaResearchWorkspace.fromJson(Map<String, dynamic> row)
    : id = _text(row, 'id', 36),
      createdAt = _instant(row['createdAt']),
      updatedAt = _instant(row['updatedAt']),
      title = _text(row, 'title', 240),
      brief = _text(row, 'brief', 4000),
      outline = _text(row, 'outline', 10000),
      subquestions = _text(row, 'subquestions', 10000),
      draft = _text(row, 'draft', 60000),
      sources = [
        for (final value in row['sources'] as List)
          ResearchSource.fromJson(_map(value)),
      ],
      claims = [
        for (final value in row['claims'] as List)
          ResearchClaim.fromJson(_map(value)),
      ],
      checks = Map<String, bool>.from(row['checks'] as Map) {
    if (row['schemaVersion'] != 1 ||
        !_uuid.hasMatch(id) ||
        updatedAt.isBefore(createdAt) ||
        sources.length > _maxSources ||
        claims.length > _maxClaims ||
        sources.map((source) => source.id).toSet().length != sources.length ||
        claims.map((claim) => claim.id).toSet().length != claims.length ||
        claims.any(
          (claim) => !sources
              .map((source) => source.id)
              .toSet()
              .containsAll(claim.sourceIds),
        ) ||
        checks.keys.toSet().length != researchChecks.length ||
        !checks.keys.toSet().containsAll(researchChecks.keys) ||
        jsonEncode(row).length > maxDiplomaResearchSnapshotCharacters) {
      throw const FormatException('Invalid saved D6 research workspace.');
    }
  }

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String title;
  final String brief;
  final String outline;
  final String subquestions;
  final String draft;
  final List<ResearchSource> sources;
  final List<ResearchClaim> claims;
  final Map<String, bool> checks;

  int get draftWordCount =>
      draft.trim().isEmpty ? 0 : RegExp(r'\S+').allMatches(draft.trim()).length;

  bool get hasSavedWork =>
      [
        title,
        brief,
        outline,
        subquestions,
        draft,
      ].any((value) => value.trim().isNotEmpty) ||
      sources.any((source) => source.hasWork) ||
      claims.any((claim) => claim.hasWork) ||
      checks.values.any((checked) => checked);

  void validateAt(DateTime now) {
    if (createdAt.isAfter(now.toUtc()) || updatedAt.isAfter(now.toUtc())) {
      throw const FormatException(
        'D6 research workspace is dated in the future.',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'title': title,
    'brief': brief,
    'outline': outline,
    'subquestions': subquestions,
    'draft': draft,
    'sources': [for (final source in sources) source.toJson()],
    'claims': [for (final claim in claims) claim.toJson()],
    'checks': checks,
  };

  /// Plain text for tutor discussion. The app neither submits nor grades it.
  String toPlainText() {
    final out = StringBuffer()
      ..writeln('D6 research workspace — formative copy')
      ..writeln('Not an official WSET submission or grade.')
      ..writeln()
      ..writeln(
        'Title: ${title.trim().isEmpty ? '(not entered)' : title.trim()}',
      )
      ..writeln('Draft word count (approximate): $draftWordCount')
      ..writeln()
      ..writeln('BRIEF / PRESENTATION REQUIREMENTS')
      ..writeln(brief.trim())
      ..writeln()
      ..writeln('OUTLINE')
      ..writeln(outline.trim())
      ..writeln()
      ..writeln('RESEARCH SUBQUESTIONS')
      ..writeln(subquestions.trim())
      ..writeln()
      ..writeln('SOURCE APPRAISAL');
    for (final (index, source) in sources.indexed) {
      out
        ..writeln('${index + 1}. ${source.citation}')
        ..writeln('   URL: ${source.url}')
        ..writeln('   Date: ${source.date}')
        ..writeln('   Scope / method: ${source.scopeMethod}')
        ..writeln('   Strength: ${source.strength}')
        ..writeln('   Limitation: ${source.limitation}');
    }
    out
      ..writeln()
      ..writeln('CLAIMS, EVIDENCE AND COUNTEREVIDENCE');
    for (final (index, claim) in claims.indexed) {
      final citations = [
        for (final source in sources)
          if (claim.sourceIds.contains(source.id))
            source.citation.trim().isEmpty
                ? '(source without citation)'
                : source.citation,
      ];
      out
        ..writeln('${index + 1}. ${claim.statement}')
        ..writeln('   Supporting sources: ${citations.join('; ')}')
        ..writeln('   Counterevidence: ${claim.counterevidence}')
        ..writeln('   Provisional conclusion: ${claim.conclusion}');
    }
    out
      ..writeln()
      ..writeln('DRAFT')
      ..writeln(draft.trim());
    out
      ..writeln()
      ..writeln('REVISION CHECKLIST');
    for (final entry in researchChecks.entries) {
      out.writeln('[${checks[entry.key] == true ? 'x' : ' '}] ${entry.value}');
    }
    return out.toString();
  }
}

class DiplomaResearchLoad {
  const DiplomaResearchLoad({this.workspace, this.unreadable = false});
  final DiplomaResearchWorkspace? workspace;
  final bool unreadable;
}

/// One learner-owned D6 workspace in backed-up user_settings, without a migration.
class DiplomaResearchRepository {
  DiplomaResearchRepository(this.db, {Clock? clock, Random? random})
    : clock = clock ?? const Clock(),
      random = random ?? Random.secure();

  final AppDatabase db;
  final Clock clock;
  final Random random;
  static const settingKey = 'd6_research_workspace_v1';
  static const recoveryPrefix = 'd6_research_recovery_v1_';

  Future<void> _requireL4() async {
    final profile = await (db.select(
      db.userProfiles,
    )..where((row) => row.id.equals(1))).getSingleOrNull();
    if (profile?.activeCertificationId != 'WSET_L4') {
      throw StateError('Choose WSET Level 4 as your study track first.');
    }
  }

  Future<String?> _setting() async => (await (db.select(
    db.userSettings,
  )..where((row) => row.name.equals(settingKey))).getSingleOrNull())?.value;

  Future<void> _put(String key, String value) => db
      .into(db.userSettings)
      .insertOnConflictUpdate(
        UserSetting(name: key, value: value, updatedAt: utcNow(clock)),
      );

  DiplomaResearchWorkspace _parse(String raw) {
    if (raw.length > maxDiplomaResearchSnapshotCharacters) {
      throw const FormatException('Saved D6 research workspace is too large.');
    }
    final workspace = DiplomaResearchWorkspace.fromJson(_map(jsonDecode(raw)));
    workspace.validateAt(utcNow(clock));
    return workspace;
  }

  Future<DiplomaResearchWorkspace> _loadStrict() async {
    final raw = await _setting();
    if (raw == null) throw StateError('Start a D6 research workspace first.');
    return _parse(raw);
  }

  Future<DiplomaResearchLoad> load() async {
    await _requireL4();
    final raw = await _setting();
    if (raw == null) return const DiplomaResearchLoad();
    try {
      return DiplomaResearchLoad(workspace: _parse(raw));
    } catch (_) {
      return const DiplomaResearchLoad(unreadable: true);
    }
  }

  Future<DiplomaResearchWorkspace> start() => db.transaction(() async {
    await _requireL4();
    if (await _setting() != null) {
      throw StateError('Open or recover the saved D6 workspace first.');
    }
    final now = utcNow(clock);
    final workspace = DiplomaResearchWorkspace.fromJson({
      'schemaVersion': 1,
      'id': newUuid(random),
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'title': '',
      'brief': '',
      'outline': '',
      'subquestions': '',
      'draft': '',
      'sources': <Object>[],
      'claims': <Object>[],
      'checks': {for (final key in researchChecks.keys) key: false},
    });
    await _put(settingKey, jsonEncode(workspace.toJson()));
    return workspace;
  });

  Future<DiplomaResearchWorkspace> _mutate(
    DiplomaResearchWorkspace Function(DiplomaResearchWorkspace) change,
  ) => db.transaction(() async {
    await _requireL4();
    final old = await _loadStrict();
    final row = change(old).toJson();
    final now = utcNow(clock);
    row['updatedAt'] = (now.isBefore(old.updatedAt) ? old.updatedAt : now)
        .toIso8601String();
    final updated = DiplomaResearchWorkspace.fromJson(row);
    await _put(settingKey, jsonEncode(updated.toJson()));
    return updated;
  });

  DiplomaResearchWorkspace _replace(
    DiplomaResearchWorkspace old,
    void Function(Map<String, dynamic>) edit,
  ) {
    final row = old.toJson();
    edit(row);
    return DiplomaResearchWorkspace.fromJson(row);
  }

  Future<DiplomaResearchWorkspace> updateText(String field, String text) {
    if (!const {
      'title',
      'brief',
      'outline',
      'subquestions',
      'draft',
    }.contains(field)) {
      throw ArgumentError.value(field, 'field');
    }
    return _mutate((old) => _replace(old, (row) => row[field] = text));
  }

  Future<DiplomaResearchWorkspace> addSource() => _mutate((old) {
    if (old.sources.length >= _maxSources) {
      throw StateError('The source log is full.');
    }
    var id = newUuid(random);
    while (old.sources.any((source) => source.id == id)) {
      id = newUuid(random);
    }
    return _replace(old, (row) {
      row['sources'] = [
        ...old.sources.map((source) => source.toJson()),
        {
          'id': id,
          'citation': '',
          'url': '',
          'date': '',
          'scopeMethod': '',
          'strength': '',
          'limitation': '',
        },
      ];
    });
  });

  Future<DiplomaResearchWorkspace> updateSource(
    String id,
    String field,
    String text,
  ) {
    if (!const {
      'citation',
      'url',
      'date',
      'scopeMethod',
      'strength',
      'limitation',
    }.contains(field)) {
      throw ArgumentError.value(field, 'field');
    }
    return _mutate((old) {
      if (!old.sources.any((source) => source.id == id)) {
        throw StateError('Source was not found.');
      }
      return _replace(old, (row) {
        row['sources'] = [
          for (final source in old.sources)
            if (source.id == id)
              {...source.toJson(), field: text}
            else
              source.toJson(),
        ];
      });
    });
  }

  Future<DiplomaResearchWorkspace> removeSource(String id) => _mutate((old) {
    if (!old.sources.any((source) => source.id == id)) {
      throw StateError('Source was not found.');
    }
    return _replace(old, (row) {
      row['sources'] = [
        for (final source in old.sources)
          if (source.id != id) source.toJson(),
      ];
      row['claims'] = [
        for (final claim in old.claims)
          {
            ...claim.toJson(),
            'sourceIds': claim.sourceIds
                .where((sourceId) => sourceId != id)
                .toList(),
          },
      ];
    });
  });

  Future<DiplomaResearchWorkspace> addClaim() => _mutate((old) {
    if (old.claims.length >= _maxClaims) {
      throw StateError('The claim map is full.');
    }
    var id = newUuid(random);
    while (old.claims.any((claim) => claim.id == id)) {
      id = newUuid(random);
    }
    return _replace(old, (row) {
      row['claims'] = [
        ...old.claims.map((claim) => claim.toJson()),
        {
          'id': id,
          'statement': '',
          'sourceIds': <String>[],
          'counterevidence': '',
          'conclusion': '',
        },
      ];
    });
  });

  Future<DiplomaResearchWorkspace> updateClaim(
    String id,
    String field,
    String text,
  ) {
    if (!const {'statement', 'counterevidence', 'conclusion'}.contains(field)) {
      throw ArgumentError.value(field, 'field');
    }
    return _mutate((old) {
      if (!old.claims.any((claim) => claim.id == id)) {
        throw StateError('Claim was not found.');
      }
      return _replace(old, (row) {
        row['claims'] = [
          for (final claim in old.claims)
            if (claim.id == id)
              {...claim.toJson(), field: text}
            else
              claim.toJson(),
        ];
      });
    });
  }

  Future<DiplomaResearchWorkspace> removeClaim(String id) => _mutate((old) {
    if (!old.claims.any((claim) => claim.id == id)) {
      throw StateError('Claim was not found.');
    }
    return _replace(old, (row) {
      row['claims'] = [
        for (final claim in old.claims)
          if (claim.id != id) claim.toJson(),
      ];
    });
  });

  Future<DiplomaResearchWorkspace> setClaimSource(
    String claimId,
    String sourceId,
    bool linked,
  ) => _mutate((old) {
    if (!old.sources.any((source) => source.id == sourceId)) {
      throw StateError('Source was not found.');
    }
    if (!old.claims.any((claim) => claim.id == claimId)) {
      throw StateError('Claim was not found.');
    }
    final sourceIds = {
      ...old.claims.singleWhere((claim) => claim.id == claimId).sourceIds,
    };
    if (linked) {
      sourceIds.add(sourceId);
    } else {
      sourceIds.remove(sourceId);
    }
    return _replace(old, (row) {
      row['claims'] = [
        for (final claim in old.claims)
          if (claim.id == claimId)
            {...claim.toJson(), 'sourceIds': sourceIds.toList()}
          else
            claim.toJson(),
      ];
    });
  });

  Future<DiplomaResearchWorkspace> setCheck(String key, bool checked) {
    if (!researchChecks.containsKey(key)) throw ArgumentError.value(key, 'key');
    return _mutate(
      (old) => _replace(old, (row) {
        row['checks'] = {...old.checks, key: checked};
      }),
    );
  }

  Future<String> exportPlainText() async {
    await _requireL4();
    return (await _loadStrict()).toPlainText();
  }

  /// Explicitly preserve an unreadable value in backup before starting fresh.
  Future<void> archiveUnreadable() => db.transaction(() async {
    await _requireL4();
    final raw = await _setting();
    if (raw == null) throw StateError('No saved D6 workspace was found.');
    try {
      _parse(raw);
    } catch (_) {
      var key = '$recoveryPrefix${newUuid(random).replaceAll('-', '_')}';
      while ((await (db.select(
            db.userSettings,
          )..where((row) => row.name.equals(key))).getSingleOrNull()) !=
          null) {
        key = '$recoveryPrefix${newUuid(random).replaceAll('-', '_')}';
      }
      await _put(key, raw);
      await (db.delete(
        db.userSettings,
      )..where((row) => row.name.equals(settingKey))).go();
      return;
    }
    throw StateError(
      'The saved D6 workspace is readable; nothing was removed.',
    );
  });
}
