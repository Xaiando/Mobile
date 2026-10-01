import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show StringExpressionOperators;

import '../curriculum/knowledge_graph.dart';
import '../database/app_database.dart';
import '../database/uuid.dart';
import '../study/study_planner.dart';
import '../tasting/tasting_practice.dart';
import '../time/utc_clock.dart';

const cmsRehearsalTrack = 'CMS_CERTIFIED';
const cmsRehearsalScopeUrl =
    'https://courtofmastersommeliers.org/wp-content/uploads/2026/02/Syllabus-202627-1.pdf';
const _maxProse = 4000;
const _topics = {'regions', 'production', 'beverages', 'business'};
const _winePrompts = {
  'description',
  'structure',
  'identity',
  'quality_faults',
  'uncertainty',
};
const _blueprint = {
  'regions': 4,
  'production': 2,
  'beverages': 2,
  'business': 2,
};
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _id = RegExp(r'^[a-z][a-z0-9_]{0,79}$');
Map<String, dynamic> _map(Object? v) => Map<String, dynamic>.from(v as Map);
List<T> _list<T>(Iterable<T> v) => List<T>.unmodifiable(v);
DateTime _savedUtc(Object? v) {
  if (v is! String) throw const FormatException('Invalid CMS practice time.');
  final p = DateTime.tryParse(v);
  if (p == null || !p.isUtc || p.toIso8601String() != v) {
    throw const FormatException('CMS practice time must be canonical UTC.');
  }
  return p;
}

void _text(String v, int max) {
  if (v.trim().isEmpty || v.length > max) {
    throw const FormatException('Empty or oversized CMS practice text.');
  }
}

List<String> _links(Object? v) {
  final ids = List<String>.from(v as List);
  if (ids.isEmpty ||
      ids.toSet().length != ids.length ||
      ids.any((id) => !RegExp(r'^ki_[a-z0-9_]+$').hasMatch(id))) {
    throw const FormatException('Invalid CMS fact links.');
  }
  return _list(ids);
}

enum CmsRehearsalSection {
  theory,
  tasting,
  service;

  String get id => name;
  String get title => switch (this) {
    theory => 'Theory practice',
    tasting => 'Two-wine deduction',
    service => 'Service decisions',
  };
  // App choices, not official examination allocations.
  int get durationSeconds => switch (this) {
    theory => 1800,
    tasting => 1200,
    service => 900,
  };
  static CmsRehearsalSection parse(Object? id) => values.singleWhere(
    (s) => s.id == id,
    orElse: () => throw const FormatException('Unsupported CMS section.'),
  );
}

class CmsRehearsalPreset {
  CmsRehearsalPreset.fromJson(Map<String, dynamic> r)
    : section = CmsRehearsalSection.parse(r['section']),
      title = r['title'] as String,
      durationSeconds = r['durationSeconds'] as int,
      mcqCount = r['mcqCount'] as int,
      writtenCount = r['writtenCount'] as int,
      wineCount = r['wineCount'] as int {
    _text(title, 100);
    if (durationSeconds != section.durationSeconds ||
        mcqCount != (section == CmsRehearsalSection.theory ? 10 : 0) ||
        writtenCount !=
            (section == CmsRehearsalSection.theory
                ? 10
                : section == CmsRehearsalSection.tasting
                ? 1
                : 3) ||
        wineCount != (section == CmsRehearsalSection.tasting ? 2 : 0)) {
      throw const FormatException('Invalid CMS app preset.');
    }
  }
  final CmsRehearsalSection section;
  final String title;
  final int durationSeconds, mcqCount, writtenCount, wineCount;
  Map<String, dynamic> toJson() => {
    'section': section.id,
    'title': title,
    'durationSeconds': durationSeconds,
    'mcqCount': mcqCount,
    'writtenCount': writtenCount,
    'wineCount': wineCount,
  };
}

typedef CmsRehearsalOption = ({String id, String text});
typedef CmsRehearsalValue = ({String key, String label});

class CmsRehearsalMcq {
  CmsRehearsalMcq.fromJson(Map<String, dynamic> r)
    : id = r['id'] as String,
      prompt = r['prompt'] as String,
      topic = r['topic'] as String,
      itemIds = _links(r['itemIds']),
      correctOptionId = r['correctOptionId'] as String,
      explanation = r['explanation'] as String,
      options = _list([
        for (final o in r['options'] as List)
          (id: _map(o)['id'] as String, text: _map(o)['text'] as String),
      ]) {
    _text(prompt, 1000);
    _text(explanation, 2000);
    if (!_id.hasMatch(id) ||
        !_topics.contains(topic) ||
        options.length != 4 ||
        options.map((o) => o.id).toSet().length != 4 ||
        options.map((o) => o.text.trim().toLowerCase()).toSet().length != 4 ||
        options.any(
          (o) =>
              !_id.hasMatch(o.id) ||
              o.text.trim().isEmpty ||
              o.text.length > 500,
        ) ||
        !options.any((o) => o.id == correctOptionId)) {
      throw const FormatException('Invalid CMS choice question.');
    }
  }
  final String id, prompt, topic, correctOptionId, explanation;
  final List<String> itemIds;
  final List<CmsRehearsalOption> options;
  Map<String, dynamic> toJson() => {
    'id': id,
    'prompt': prompt,
    'topic': topic,
    'itemIds': itemIds.toList(),
    'options': [
      for (final o in options) {'id': o.id, 'text': o.text},
    ],
    'correctOptionId': correctOptionId,
    'explanation': explanation,
  };
}

class CmsRehearsalCriterion {
  CmsRehearsalCriterion.fromJson(Map<String, dynamic> r)
    : id = r['id'] as String,
      text = r['text'] as String,
      itemIds = _links(r['itemIds']) {
    _text(text, 1500);
    if (!_id.hasMatch(id)) {
      throw const FormatException('Invalid CMS criterion.');
    }
  }
  final String id, text;
  final List<String> itemIds;
  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'itemIds': itemIds.toList(),
  };
}

class CmsRehearsalWritten {
  CmsRehearsalWritten.fromJson(Map<String, dynamic> r)
    : id = r['id'] as String,
      section = CmsRehearsalSection.parse(r['section']),
      prompt = r['prompt'] as String,
      topic = r['topic'] as String,
      criteria = _list([
        for (final c in r['criteria'] as List)
          CmsRehearsalCriterion.fromJson(_map(c)),
      ]) {
    _text(prompt, 3000);
    if (!_id.hasMatch(id) ||
        criteria.isEmpty ||
        criteria.length > 4 ||
        criteria.map((c) => c.id).toSet().length != criteria.length ||
        (section == CmsRehearsalSection.theory &&
            (!_topics.contains(topic) || criteria.length != 1)) ||
        (section != CmsRehearsalSection.theory &&
            (topic != section.id || criteria.length != 4))) {
      throw const FormatException('Invalid CMS written prompt.');
    }
  }
  final String id, prompt, topic;
  final CmsRehearsalSection section;
  final List<CmsRehearsalCriterion> criteria;
  Set<String> get itemIds => {for (final c in criteria) ...c.itemIds};
  Map<String, dynamic> toJson() => {
    'id': id,
    'section': section.id,
    'prompt': prompt,
    'topic': topic,
    'criteria': [for (final c in criteria) c.toJson()],
  };
}

class CmsRehearsalPrompt {
  CmsRehearsalPrompt.fromJson(Map<String, dynamic> r)
    : id = r['id'] as String,
      prompt = r['prompt'] as String {
    _text(prompt, 1000);
    if (!_winePrompts.contains(id)) {
      throw const FormatException('Invalid CMS wine prompt.');
    }
  }
  final String id, prompt;
  Map<String, dynamic> toJson() => {'id': id, 'prompt': prompt};
}

class CmsRehearsalAttribute {
  CmsRehearsalAttribute.fromJson(Map<String, dynamic> r)
    : key = r['key'] as String,
      label = r['label'] as String,
      section = r['section'] as String,
      isRequired = r['isRequired'] as bool,
      isSingle = r['isSingle'] as bool,
      values = _list([
        for (final v in r['values'] as List)
          (key: _map(v)['key'] as String, label: _map(v)['label'] as String),
      ]) {
    _text(label, 200);
    _text(section, 100);
    if (!_id.hasMatch(key) ||
        values.isEmpty ||
        values.length > 64 ||
        values.map((v) => v.key).toSet().length != values.length ||
        values.any(
          (v) =>
              !_id.hasMatch(v.key) ||
              v.label.trim().isEmpty ||
              v.label.length > 200,
        )) {
      throw const FormatException('Invalid CMS tasting vocabulary.');
    }
  }
  final String key, label, section;
  final bool isRequired, isSingle;
  final List<CmsRehearsalValue> values;
  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'section': section,
    'isRequired': isRequired,
    'isSingle': isSingle,
    'values': [
      for (final v in values) {'key': v.key, 'label': v.label},
    ],
  };
  static CmsRehearsalAttribute fromGrid(GridAttribute a) =>
      CmsRehearsalAttribute.fromJson({
        'key': a.key,
        'label': a.attribute.label,
        'section': a.attribute.section,
        'isRequired': a.attribute.isRequired,
        'isSingle': a.isSingle,
        'values': [
          for (final v in a.values) {'key': v.valueKey, 'label': v.label},
        ],
      });
}

class CmsRehearsalWine {
  CmsRehearsalWine.fromJson(Map<String, dynamic> r)
    : ordinal = r['ordinal'] as int,
      attributes = _list([
        for (final a in r['attributes'] as List)
          CmsRehearsalAttribute.fromJson(_map(a)),
      ]),
      observations = Map.unmodifiable({
        for (final e in _map(r['observations']).entries)
          e.key: Set<String>.unmodifiable(List<String>.from(e.value as List)),
      }),
      evidence = Map.unmodifiable(
        Map<String, String>.from(_map(r['evidence'])),
      ) {
    if (ordinal < 0 ||
        ordinal > 1 ||
        attributes.isEmpty ||
        attributes.length > 64 ||
        attributes.map((a) => a.key).toSet().length != attributes.length ||
        _map(r['observations']).values
            .any((v) => (v as List).toSet().length != v.length) ||
        observations.entries.any(
          (e) => !attributes.any(
            (a) =>
                a.key == e.key &&
                (!a.isSingle || e.value.length <= 1) &&
                e.value.every((v) => a.values.any((o) => o.key == v)),
          ),
        ) ||
        evidence.entries.any(
          (e) => !_winePrompts.contains(e.key) || e.value.length > _maxProse,
        )) {
      throw const FormatException('Invalid CMS wine snapshot.');
    }
  }
  final int ordinal;
  final List<CmsRehearsalAttribute> attributes;
  final Map<String, Set<String>> observations;
  final Map<String, String> evidence;
  bool get isComplete =>
      attributes.every(
        (a) =>
            !a.isRequired ||
            (observations[a.key] ?? const <String>{}).isNotEmpty,
      ) &&
      _winePrompts.every((id) => (evidence[id] ?? '').trim().isNotEmpty);
  Map<String, dynamic> toJson() => {
    'ordinal': ordinal,
    'attributes': [for (final a in attributes) a.toJson()],
    'observations': {
      for (final e in observations.entries) e.key: e.value.toList(),
    },
    'evidence': {...evidence},
  };
}

class CmsRehearsalBank {
  CmsRehearsalBank.fromJson(String text) {
    final r = _map(jsonDecode(text));
    if (r['schemaVersion'] != 1 ||
        r['trackId'] != cmsRehearsalTrack ||
        r['gridId'] != 'tg_deductive' ||
        r['scopeUrl'] != cmsRehearsalScopeUrl) {
      throw const FormatException('Unsupported CMS Europe bank.');
    }
    version = r['version'] as String;
    scopeVersion = r['scopeVersion'] as String;
    _text(version, 40);
    _text(scopeVersion, 40);
    presets = _list([
      for (final p in r['presets'] as List)
        CmsRehearsalPreset.fromJson(_map(p)),
    ]);
    mcqs = _list([
      for (final q in r['mcqs'] as List) CmsRehearsalMcq.fromJson(_map(q)),
    ]);
    written = _list([
      for (final q in r['written'] as List)
        CmsRehearsalWritten.fromJson(_map(q)),
    ]);
    wineEvidencePrompts = _list([
      for (final p in r['wineEvidencePrompts'] as List)
        CmsRehearsalPrompt.fromJson(_map(p)),
    ]);
    if (presets.length != 3 ||
        presets.map((p) => p.section).toSet().length != 3 ||
        mcqs.map((q) => q.id).toSet().length != mcqs.length ||
        written.map((q) => q.id).toSet().length != written.length ||
        {...mcqs.map((q) => q.id), ...written.map((q) => q.id)}.length !=
            mcqs.length + written.length ||
        wineEvidencePrompts.length != 5 ||
        wineEvidencePrompts.map((p) => p.id).toSet().length != 5) {
      throw const FormatException('Incomplete or duplicate CMS bank.');
    }
    for (final b in _blueprint.entries) {
      if (mcqs.where((q) => q.topic == b.key).length < b.value ||
          written
                  .where(
                    (q) =>
                        q.section == CmsRehearsalSection.theory &&
                        q.topic == b.key,
                  )
                  .length <
              b.value) {
        throw const FormatException('Insufficient CMS theory pool.');
      }
    }
    if (written.where((q) => q.section == CmsRehearsalSection.service).length <
            3 ||
        written.where((q) => q.section == CmsRehearsalSection.tasting).length !=
            1) {
      throw const FormatException('Incomplete CMS service/tasting pool.');
    }
  }
  late final String version, scopeVersion;
  late final List<CmsRehearsalPreset> presets;
  late final List<CmsRehearsalMcq> mcqs;
  late final List<CmsRehearsalWritten> written;
  late final List<CmsRehearsalPrompt> wineEvidencePrompts;
  CmsRehearsalPreset preset(CmsRehearsalSection s) =>
      presets.singleWhere((p) => p.section == s);
}

const _deductiveKeys = {
  'clarity',
  'brightness',
  'hue',
  'concentration',
  'rim',
  'fruit_state',
  'fruit',
  'non_fruit',
  'wood',
  'intensity',
  'dryness',
  'body',
  'acid',
  'alcohol',
  'tannin',
  'complexity',
  'finish',
  'climate',
  'style',
  'age',
};

/// Self-contained CMS practice. Physical deductions are learner observations.
class CmsRehearsalAttempt {
  CmsRehearsalAttempt.fromJson(Map<String, dynamic> r)
    : id = r['id'] as String,
      preset = CmsRehearsalPreset.fromJson(_map(r['preset'])),
      bankVersion = r['bankVersion'] as String,
      scopeVersion = r['scopeVersion'] as String,
      startedAt = _savedUtc(r['startedAt']),
      deadline = _savedUtc(r['deadline']),
      completedAt = r['completedAt'] == null
          ? null
          : _savedUtc(r['completedAt']),
      reviewedAt = r['reviewedAt'] == null ? null : _savedUtc(r['reviewedAt']),
      finishReason = r['finishReason'] as String?,
      physicalAcknowledged = r['physicalAcknowledged'] as bool,
      mcqs = _list([
        for (final q in r['mcqs'] as List) CmsRehearsalMcq.fromJson(_map(q)),
      ]),
      written = _list([
        for (final q in r['written'] as List)
          CmsRehearsalWritten.fromJson(_map(q)),
      ]),
      wines = _list([
        for (final w in r['wines'] as List) CmsRehearsalWine.fromJson(_map(w)),
      ]),
      wineEvidencePrompts = _list([
        for (final p in r['wineEvidencePrompts'] as List)
          CmsRehearsalPrompt.fromJson(_map(p)),
      ]),
      answers = Map.unmodifiable(Map<String, String>.from(_map(r['answers']))),
      prose = Map.unmodifiable(Map<String, String>.from(_map(r['prose']))),
      reviewNotes = Map.unmodifiable(
        Map<String, String>.from(_map(r['reviewNotes'])),
      ),
      selfAssessment = Map.unmodifiable({
        for (final e in _map(r['selfAssessment']).entries)
          e.key: Set<String>.unmodifiable(List<String>.from(e.value as List)),
      }) {
    _text(bankVersion, 40);
    _text(scopeVersion, 40);
    if (r['schemaVersion'] != 1 ||
        r['kind'] != 'cms_certified_rehearsal' ||
        r['trackId'] != cmsRehearsalTrack ||
        r['scopeUrl'] != cmsRehearsalScopeUrl ||
        !_uuid.hasMatch(id) ||
        deadline.difference(startedAt) !=
            Duration(seconds: preset.durationSeconds) ||
        mcqs.length != preset.mcqCount ||
        written.length != preset.writtenCount ||
        wines.length != preset.wineCount ||
        written.any((q) => q.section != section) ||
        {...mcqs.map((q) => q.id), ...written.map((q) => q.id)}.length !=
            mcqs.length + written.length ||
        (completedAt == null) != (finishReason == null) ||
        (finishReason != null &&
            !const {
              'submitted',
              'expired',
              'abandoned',
            }.contains(finishReason)) ||
        (completedAt != null &&
            (completedAt!.isBefore(startedAt) ||
                completedAt!.isAfter(deadline))) ||
        (finishReason == 'expired' && completedAt != deadline) ||
        (reviewedAt != null &&
            (completedAt == null ||
                isAbandoned ||
                reviewedAt!.isBefore(completedAt!))) ||
        answers.entries.any(
          (e) => !mcqs.any(
            (q) => q.id == e.key && q.options.any((o) => o.id == e.value),
          ),
        ) ||
        prose.entries.any(
          (e) =>
              !written.any((q) => q.id == e.key) || e.value.length > _maxProse,
        ) ||
        reviewNotes.entries.any(
          (e) =>
              !written.any((q) => q.id == e.key) ||
              e.value.trim().isEmpty ||
              e.value.length > _maxProse,
        ) ||
        selfAssessment.entries.any(
          (e) => !written.any(
            (q) =>
                q.id == e.key &&
                e.value.every((c) => q.criteria.any((v) => v.id == c)),
          ),
        ) ||
        _map(r['selfAssessment']).values
            .any((v) => (v as List).toSet().length != v.length) ||
        reviewNotes.keys
            .toSet()
            .difference(selfAssessment.keys.toSet())
            .isNotEmpty ||
        selfAssessment.keys
            .toSet()
            .difference(reviewNotes.keys.toSet())
            .isNotEmpty ||
        (selfAssessment.isNotEmpty &&
            (!isFinished ||
                isAbandoned ||
                selfAssessment.keys.any(
                  (id) => (prose[id] ?? '').trim().isEmpty,
                ))) ||
        (section != CmsRehearsalSection.tasting &&
            (physicalAcknowledged || wineEvidencePrompts.isNotEmpty)) ||
        (section == CmsRehearsalSection.tasting &&
            (wineEvidencePrompts.length != 5 ||
                wineEvidencePrompts.map((p) => p.id).toSet().length != 5 ||
                wines.asMap().entries.any((e) => e.value.ordinal != e.key) ||
                jsonEncode(
                      wines.first.attributes.map((a) => a.toJson()).toList(),
                    ) !=
                    jsonEncode(
                      wines.last.attributes.map((a) => a.toJson()).toList(),
                    ))) ||
        (reviewedAt != null &&
            (!isComplete ||
                written.any((q) => !selfAssessment.containsKey(q.id)))) ||
        jsonEncode(r).length > 300000) {
      throw const FormatException('Invalid saved CMS attempt.');
    }
    if (section == CmsRehearsalSection.theory) {
      for (final b in _blueprint.entries) {
        if (mcqs.where((q) => q.topic == b.key).length != b.value ||
            written.where((q) => q.topic == b.key).length != b.value) {
          throw const FormatException('Invalid saved CMS theory composition.');
        }
      }
    }
    for (final w in wines) {
      if (w.attributes.length != 20 ||
          !w.attributes.map((a) => a.key).toSet().containsAll(_deductiveKeys) ||
          w.attributes.any(
            (a) =>
                a.isRequired !=
                    (!const {'fruit', 'non_fruit'}.contains(a.key)) ||
                a.isSingle != (!const {'fruit', 'non_fruit'}.contains(a.key)),
          )) {
        throw const FormatException('Incomplete CMS deductive dimensions.');
      }
    }
  }
  final String id, bankVersion, scopeVersion;
  final CmsRehearsalPreset preset;
  final DateTime startedAt, deadline;
  final DateTime? completedAt, reviewedAt;
  final String? finishReason;
  final bool physicalAcknowledged;
  final List<CmsRehearsalMcq> mcqs;
  final List<CmsRehearsalWritten> written;
  final List<CmsRehearsalWine> wines;
  final List<CmsRehearsalPrompt> wineEvidencePrompts;
  final Map<String, String> answers, prose, reviewNotes;
  final Map<String, Set<String>> selfAssessment;
  CmsRehearsalSection get section => preset.section;
  bool get isFinished => completedAt != null;
  bool get isAbandoned => finishReason == 'abandoned';
  bool get isReviewed => reviewedAt != null;
  int get mcqCorrect =>
      mcqs.where((q) => answers[q.id] == q.correctOptionId).length;
  bool get isComplete => missingReasons.isEmpty;
  List<String> get missingReasons => [
    if (mcqs.any((q) => !answers.containsKey(q.id)))
      'Answer each theory choice.',
    if (written.any((q) => (prose[q.id] ?? '').trim().isEmpty))
      'Write each response.',
    if (section == CmsRehearsalSection.tasting && !physicalAcknowledged)
      'Confirm these observations describe two actual wines.',
    for (final w in wines)
      if (!w.isComplete)
        'Complete Wine ${w.ordinal + 1} observations and evidence.',
  ];
  Duration remaining(DateTime now) {
    if (isFinished) return Duration.zero;
    final effective = now.toUtc().isBefore(startedAt) ? startedAt : now.toUtc();
    final left = deadline.difference(effective);
    return left.isNegative ? Duration.zero : left;
  }

  void validateAt(DateTime now) {
    final instant = toStorageInstant(now);
    if (startedAt.isAfter(instant) ||
        (completedAt?.isAfter(instant) ?? false) ||
        (reviewedAt?.isAfter(instant) ?? false)) {
      throw const FormatException('CMS practice is dated in the future.');
    }
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'kind': 'cms_certified_rehearsal',
    'trackId': cmsRehearsalTrack,
    'scopeUrl': cmsRehearsalScopeUrl,
    'id': id,
    'preset': preset.toJson(),
    'bankVersion': bankVersion,
    'scopeVersion': scopeVersion,
    'startedAt': startedAt.toIso8601String(),
    'deadline': deadline.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'reviewedAt': reviewedAt?.toIso8601String(),
    'finishReason': finishReason,
    'physicalAcknowledged': physicalAcknowledged,
    'mcqs': [for (final q in mcqs) q.toJson()],
    'written': [for (final q in written) q.toJson()],
    'wines': [for (final w in wines) w.toJson()],
    'wineEvidencePrompts': [for (final p in wineEvidencePrompts) p.toJson()],
    'answers': {...answers},
    'prose': {...prose},
    'reviewNotes': {...reviewNotes},
    'selfAssessment': {
      for (final e in selfAssessment.entries) e.key: e.value.toList(),
    },
  };
}

class _CmsOutcome {
  const _CmsOutcome({this.attempt, this.error, this.stack});
  final CmsRehearsalAttempt? attempt;
  final Object? error;
  final StackTrace? stack;
}

/// Persisted CMS-only practice: no memory state, exam pass or WSET writes.
class CmsRehearsalRepository {
  CmsRehearsalRepository(
    this.db, {
    required this.bank,
    Clock? clock,
    Random? random,
  }) : clock = clock ?? const Clock(),
       random = random ?? Random.secure();
  final AppDatabase db;
  final CmsRehearsalBank bank;
  final Clock clock;
  final Random random;
  static const currentKey = 'cms_rehearsal_current_v1';
  static const attemptPrefix = 'cms_rehearsal_attempt_v1_';
  static String keyFor(String id) => attemptPrefix + id.replaceAll('-', '_');
  Future<String?> _setting(String name) async => (await (db.select(
    db.userSettings,
  )..where((r) => r.name.equals(name))).getSingleOrNull())?.value;
  Future<void> _put(String name, String value) => db
      .into(db.userSettings)
      .insertOnConflictUpdate(
        UserSetting(name: name, value: value, updatedAt: utcNow(clock)),
      );
  Future<void> _save(CmsRehearsalAttempt a) =>
      _put(keyFor(a.id), jsonEncode(a.toJson()));
  Future<CmsRehearsalAttempt> _load(String id) async {
    if (!_uuid.hasMatch(id)) {
      throw const FormatException('Invalid CMS selection.');
    }
    final text = await _setting(keyFor(id));
    if (text == null) throw StateError('CMS practice not found.');
    final a = CmsRehearsalAttempt.fromJson(_map(jsonDecode(text)));
    if (a.id != id) throw const FormatException('CMS identity/key mismatch.');
    a.validateAt(utcNow(clock));
    return a;
  }

  Future<void> _clearIfMatches(String id) async {
    if (await _setting(currentKey) == id) {
      await (db.delete(
        db.userSettings,
      )..where((r) => r.name.equals(currentKey))).go();
    }
  }

  CmsRehearsalAttempt _ended(CmsRehearsalAttempt a, String reason) {
    final now = utcNow(clock);
    final expired = reason == 'expired' || !now.isBefore(a.deadline);
    return CmsRehearsalAttempt.fromJson({
      ...a.toJson(),
      'completedAt':
          (expired
                  ? a.deadline
                  : now.isBefore(a.startedAt)
                  ? a.startedAt
                  : now)
              .toIso8601String(),
      'finishReason': expired ? 'expired' : reason,
    });
  }

  Future<CmsRehearsalAttempt> _expire(CmsRehearsalAttempt a) async {
    if (!a.isFinished && !utcNow(clock).isBefore(a.deadline)) {
      a = _ended(a, 'expired');
      await _save(a);
      await _clearIfMatches(a.id);
    }
    return a;
  }

  Future<CmsRehearsalAttempt?> _currentInTransaction() async {
    final id = await _setting(currentKey);
    if (id == null) return null;
    final a = await _expire(await _load(id));
    return a.isFinished ? null : a;
  }

  Future<CmsRehearsalAttempt?> current() =>
      db.transaction(_currentInTransaction);
  Future<CmsRehearsalAttempt> read(String id) =>
      db.transaction(() async => _expire(await _load(id)));
  Future<CmsRehearsalAttempt> resume(String id) => db.transaction(() async {
    final a = await _expire(await _load(id));
    if (!a.isFinished) {
      final active = await _currentInTransaction();
      if (active != null && active.id != id) {
        throw StateError('Resume or end current CMS practice first.');
      }
      await _put(currentKey, id);
    }
    return a;
  });

  Future<CmsRehearsalAttempt> start(CmsRehearsalSection section) async {
    final outcome = await db.transaction(() async {
      final active = await _currentInTransaction();
      if (active != null) {
        return _CmsOutcome(
          error: StateError('Resume or end saved CMS practice first.'),
          stack: StackTrace.current,
        );
      }
      CmsRehearsalAttempt a;
      try {
        final preset = bank.preset(section);
        final mappings = await StudyPlanner(
          db,
          clock: clock,
        ).effectiveMappings(cmsRehearsalTrack);
        final ids = {
          for (final i in await KnowledgeGraph(db, clock: clock).currentItems())
            i.id,
        };
        bool linked(Iterable<String> links) =>
            links.every((id) => mappings.containsKey(id) && ids.contains(id));
        final mcqs = <CmsRehearsalMcq>[];
        final written = <CmsRehearsalWritten>[];
        if (section == CmsRehearsalSection.theory) {
          for (final b in _blueprint.entries) {
            final choices =
                bank.mcqs
                    .where((q) => q.topic == b.key && linked(q.itemIds))
                    .toList()
                  ..shuffle(random);
            final replies =
                bank.written
                    .where(
                      (q) =>
                          q.section == section &&
                          q.topic == b.key &&
                          linked(q.itemIds),
                    )
                    .toList()
                  ..shuffle(random);
            if (choices.length < b.value || replies.length < b.value) {
              throw StateError('Not enough current CMS ${b.key} practice.');
            }
            mcqs.addAll(choices.take(b.value));
            written.addAll(replies.take(b.value));
          }
          mcqs.shuffle(random);
          written.shuffle(random);
        } else {
          final pool =
              bank.written
                  .where((q) => q.section == section && linked(q.itemIds))
                  .toList()
                ..shuffle(random);
          if (pool.length < preset.writtenCount) {
            throw StateError('Not enough current CMS ${section.id} practice.');
          }
          written.addAll(pool.take(preset.writtenCount));
        }
        final wines = <Map<String, dynamic>>[];
        if (section == CmsRehearsalSection.tasting) {
          final grid = await TastingPractice(
            db,
            clock: clock,
          ).layout('tg_deductive');
          if (grid.attributes.isEmpty) {
            throw StateError('CMS vocabulary unavailable.');
          }
          for (var i = 0; i < 2; i++) {
            wines.add({
              'ordinal': i,
              'attributes': [
                for (final a in grid.attributes)
                  CmsRehearsalAttribute.fromGrid(a).toJson(),
              ],
              'observations': <String, List<String>>{},
              'evidence': <String, String>{},
            });
          }
        }
        var id = newUuid(random);
        while (await _setting(keyFor(id)) != null) {
          id = newUuid(random);
        }
        final now = utcNow(clock);
        a = CmsRehearsalAttempt.fromJson({
          'schemaVersion': 1,
          'kind': 'cms_certified_rehearsal',
          'trackId': cmsRehearsalTrack,
          'scopeUrl': cmsRehearsalScopeUrl,
          'id': id,
          'preset': preset.toJson(),
          'bankVersion': bank.version,
          'scopeVersion': bank.scopeVersion,
          'startedAt': now.toIso8601String(),
          'deadline': now
              .add(Duration(seconds: preset.durationSeconds))
              .toIso8601String(),
          'completedAt': null,
          'reviewedAt': null,
          'finishReason': null,
          'physicalAcknowledged': false,
          'mcqs': [
            for (final q in mcqs)
              {
                ...q.toJson(),
                'options': ([
                  for (final o in q.options) {'id': o.id, 'text': o.text},
                ]..shuffle(random)),
              },
          ],
          'written': [for (final q in written) q.toJson()],
          'wines': wines,
          'wineEvidencePrompts': section == CmsRehearsalSection.tasting
              ? [for (final p in bank.wineEvidencePrompts) p.toJson()]
              : <Map<String, dynamic>>[],
          'answers': <String, String>{},
          'prose': <String, String>{},
          'reviewNotes': <String, String>{},
          'selfAssessment': <String, List<String>>{},
        });
      } catch (error, stack) {
        if (error is! FormatException &&
            error is! StateError &&
            error is! ArgumentError &&
            error is! TypeError) {
          rethrow;
        }
        return _CmsOutcome(error: error, stack: stack);
      }
      // Storage writes remain outside the validation catch and roll back on failure.
      await _save(a);
      await _put(currentKey, a.id);
      return _CmsOutcome(attempt: a);
    });
    if (outcome.error != null) {
      Error.throwWithStackTrace(outcome.error!, outcome.stack!);
    }
    return outcome.attempt!;
  }

  Future<CmsRehearsalAttempt> _change(
    String id,
    void Function(Map<String, dynamic>) mutate, {
    bool afterFinish = false,
  }) async {
    final outcome = await db.transaction(() async {
      final a = await _expire(await _load(id));
      if (a.isReviewed ||
          (afterFinish ? !a.isFinished || a.isAbandoned : a.isFinished)) {
        return _CmsOutcome(
          error: StateError('CMS practice is not editable in this state.'),
          stack: StackTrace.current,
        );
      }
      CmsRehearsalAttempt changed;
      try {
        final row = a.toJson();
        if (!afterFinish) {
          row['reviewedAt'] = null;
          row['reviewNotes'] = <String, String>{};
          row['selfAssessment'] = <String, List<String>>{};
        }
        mutate(row);
        changed = CmsRehearsalAttempt.fromJson(row);
        changed.validateAt(utcNow(clock));
      } catch (error, stack) {
        if (error is! FormatException &&
            error is! StateError &&
            error is! ArgumentError &&
            error is! TypeError) {
          rethrow;
        }
        return _CmsOutcome(error: error, stack: stack);
      }
      await _save(changed);
      return _CmsOutcome(attempt: changed);
    });
    if (outcome.error != null) {
      Error.throwWithStackTrace(outcome.error!, outcome.stack!);
    }
    return outcome.attempt!;
  }

  Future<CmsRehearsalAttempt> answerMcq(
    String id,
    String questionId,
    String optionId,
  ) => _change(id, (r) {
    (r['answers'] as Map)[questionId] = optionId;
  });
  Future<CmsRehearsalAttempt> answerWritten(
    String id,
    String questionId,
    String text,
  ) {
    return _change(id, (r) {
      if (text.length > _maxProse) {
        throw ArgumentError('CMS response too long.');
      }
      (r['prose'] as Map)[questionId] = text;
    });
  }

  Future<CmsRehearsalAttempt> chooseObservation(
    String id,
    int wineIndex,
    String key,
    Set<String> values,
  ) => _change(id, (r) {
    final wines = r['wines'] as List;
    if (wineIndex < 0 || wineIndex >= wines.length) {
      throw ArgumentError.value(wineIndex, 'wineIndex');
    }
    (_map(wines[wineIndex])['observations'] as Map)[key] = values.toList();
  });
  Future<CmsRehearsalAttempt> writeWineEvidence(
    String id,
    int wineIndex,
    String promptId,
    String text,
  ) {
    return _change(id, (r) {
      if (text.length > _maxProse) {
        throw ArgumentError('CMS wine evidence too long.');
      }
      final wines = r['wines'] as List;
      if (wineIndex < 0 || wineIndex >= wines.length) {
        throw ArgumentError.value(wineIndex, 'wineIndex');
      }
      (_map(wines[wineIndex])['evidence'] as Map)[promptId] = text;
    });
  }

  Future<CmsRehearsalAttempt> acknowledgePhysical(String id, bool value) =>
      _change(id, (r) {
        r['physicalAcknowledged'] = value;
      });
  Future<CmsRehearsalAttempt> finish(String id) => db.transaction(() async {
    var a = await _expire(await _load(id));
    if (!a.isFinished) {
      a = _ended(a, 'submitted');
      await _save(a);
    }
    await _clearIfMatches(id);
    return a;
  });
  Future<CmsRehearsalAttempt> selfAssess(
    String id,
    String questionId,
    Set<String> criterionIds, {
    required String improvement,
  }) {
    return _change(id, (r) {
      if (improvement.trim().isEmpty || improvement.length > _maxProse) {
        throw ArgumentError(
          'Record a nonblank improvement note of at most 4000 characters.',
        );
      }
      (r['selfAssessment'] as Map)[questionId] = criterionIds.toList();
      (r['reviewNotes'] as Map)[questionId] = improvement;
    }, afterFinish: true);
  }

  Future<CmsRehearsalAttempt> review(String id) => _change(id, (r) {
    final a = CmsRehearsalAttempt.fromJson(r);
    if (!a.isComplete ||
        a.written.any((q) => !a.selfAssessment.containsKey(q.id))) {
      throw StateError(
        'Complete saved responses and each improvement-led review first.',
      );
    }
    r['reviewedAt'] = utcNow(clock).toIso8601String();
  }, afterFinish: true);
  Future<({List<CmsRehearsalAttempt> entries, int unreadableCount})>
  historyWithDiagnostics() => db.transaction(() async {
    final rows = await (db.select(
      db.userSettings,
    )..where((r) => r.name.like('$attemptPrefix%'))).get();
    final entries = <CmsRehearsalAttempt>[];
    var unreadable = 0;
    for (final r in rows) {
      if (!r.name.startsWith(attemptPrefix)) continue;
      CmsRehearsalAttempt a;
      try {
        a = CmsRehearsalAttempt.fromJson(_map(jsonDecode(r.value)));
        if (keyFor(a.id) != r.name) {
          throw const FormatException('CMS history key mismatch.');
        }
        a.validateAt(utcNow(clock));
      } catch (e) {
        if (e is! FormatException &&
            e is! TypeError &&
            e is! StateError &&
            e is! ArgumentError) {
          rethrow;
        }
        unreadable++;
        continue;
      }
      entries.add(await _expire(a));
    }
    entries.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return (entries: _list(entries), unreadableCount: unreadable);
  });
  Future<CmsRehearsalAttempt?> leaveFinished(String id) =>
      db.transaction(() async {
        if (!(await _expire(await _load(id))).isFinished) {
          throw StateError('Finish or end this CMS practice first.');
        }
        await _clearIfMatches(id);
        return _currentInTransaction();
      });
  Future<void> discardCurrent({String? expectedId}) => db.transaction(() async {
    final id = await _setting(currentKey);
    if (expectedId != null && id != expectedId) {
      throw StateError('CMS selection changed. Reopen it first.');
    }
    if (id != null) {
      final a = await _expire(await _load(id));
      if (!a.isFinished) await _save(_ended(a, 'abandoned'));
      await _clearIfMatches(id);
    }
  });
  Future<String?> currentPointer() => _setting(currentKey);
  Future<void> resetCurrentPointer({required String expectedId}) =>
      db.transaction(() async {
        final observed = await _setting(currentKey);
        if (observed != expectedId) {
          throw StateError('CMS selection changed. Reload it first.');
        }
        var unreadable = false;
        try {
          await _load(expectedId);
        } catch (error) {
          // Only record-domain damage or an absent row qualifies for pointer-only recovery.
          if (error is FormatException ||
              error is TypeError ||
              error is ArgumentError) {
            unreadable = true;
          } else if (error is StateError &&
              error.message == 'CMS practice not found.') {
            unreadable = true;
          } else {
            rethrow;
          }
        }
        if (!unreadable) {
          throw StateError('CMS practice is readable again. Reload it first.');
        }
        await (db.delete(
          db.userSettings,
        )..where((r) => r.name.equals(currentKey))).go();
      });
}
