import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Variable;

import '../curriculum/curriculum_catalog.dart';
import '../audio/tasting_audio.dart';
import '../database/app_database.dart';
import '../diploma_written/diploma_written.dart';
import '../diploma_tasting/diploma_tasting_flight.dart';
import '../diploma_tasting/d3_tasting_paper.dart';
import '../diploma_research/diploma_research.dart';
import '../rehearsal/rehearsal.dart';
import '../tasting_guidance/guided_tasting.dart';
import '../tasting_pair/tasting_pair.dart';
import '../time/utc_clock.dart';
import '../cms_rehearsal/cms_rehearsal.dart';

/// A review package, deliberately separate from the private full backup.
/// No onboarding, settings, journal photos or FSRS internals are exported.
class ReviewExport {
  ReviewExport(this.db, {Clock? clock}) : clock = clock ?? const Clock();
  final AppDatabase db;
  final Clock clock;
  static const maxExportBytes = 64 * 1024 * 1024;
  static const maxRows = 50000;
  static const notice =
      'App practice only; not an official WSET or CMS result. '
      'FSRS ratings are memory ratings, not marks. Written/tasting rubrics are '
      'self-reviews, not expert assessments. Question context is from the current '
      'installed curriculum and may differ from the original presentation. '
      'These editable exports are not tamper-proof certificates.';

  Future<Map<String, Object?>> snapshot({
    bool includeAudio = false,
    String? tastingId,
  }) => db.transaction(() async {
    Future<List<Map<String, Object?>>> rows(
      String sql, [
      List<Variable> vars = const [],
    ]) async {
      final result = await db
          .customSelect('$sql LIMIT ${maxRows + 1}', variables: vars)
          .get();
      if (result.length > maxRows) {
        throw StateError(
          'There are more than $maxRows records. Export a private backup instead.',
        );
      }
      return [for (final r in result) r.data];
    }

    final release = await CurriculumCatalog(db).installedRelease();
    final sessions = await rows(
      'SELECT id, tasting_grid_id, is_blind, started_at, completed_at, notes FROM tasting_sessions '
      '${tastingId == null ? "" : "WHERE id = ?"} ORDER BY started_at',
      [if (tastingId != null) Variable(tastingId)],
    );
    if (tastingId != null && sessions.isEmpty) {
      throw StateError('This tasting no longer exists.');
    }
    final descriptors = await rows(
      'SELECT d.tasting_session_id, a.section, a.label AS attribute, v.label AS answer, '
      'd.attribute_key, d.value_key FROM tasting_descriptors d '
      'JOIN tasting_grid_attributes a ON a.tasting_grid_id = d.tasting_grid_id AND a.attribute_key = d.attribute_key '
      'JOIN tasting_grid_values v ON v.tasting_grid_id = d.tasting_grid_id AND v.attribute_key = d.attribute_key AND v.value_key = d.value_key '
      '${tastingId == null ? "" : "WHERE d.tasting_session_id = ?"} ORDER BY d.tasting_session_id, a.position, v.position',
      [if (tastingId != null) Variable(tastingId)],
    );
    final reviews = tastingId != null
        ? <Map<String, Object?>>[]
        : await rows(
            'SELECT e.id, e.exercise_id, e.reviewed_at, e.knowledge_item_id, '
            'e.question_template_id, t.mode, t.direction, q.prompt_text AS current_prompt, i.assertion_text AS current_assertion, '
            'i.verification_status, e.answer_payload, e.selected_node_id, n.name AS selected_label, '
            'e.rating AS memory_rating, e.response_ms, e.seed FROM review_events e '
            'JOIN knowledge_items i ON i.id = e.knowledge_item_id '
            'JOIN question_templates t ON t.id = e.question_template_id '
            'LEFT JOIN questions q ON q.knowledge_item_id = e.knowledge_item_id AND q.question_template_id = e.question_template_id '
            'LEFT JOIN knowledge_nodes n ON n.id = e.selected_node_id ORDER BY e.reviewed_at, e.id',
          );
    final options = tastingId != null
        ? <Map<String, Object?>>[]
        : await rows(
            'SELECT o.review_event_id, o.position, o.knowledge_node_id, n.name AS label '
            'FROM review_event_options o JOIN knowledge_nodes n ON n.id = o.knowledge_node_id ORDER BY o.review_event_id, o.position',
          );
    final prefixes = [
      DiplomaWrittenRepository.attemptPrefix,
      DiplomaTastingFlightRepository.flightPrefix,
      D3TastingPaperRepository.paperPrefix,
      RehearsalRepository.attemptPrefix,
      GuidedTastingRepository.recordPrefix,
      TastingPairRepository.attemptPrefix,
      CmsRehearsalRepository.attemptPrefix,
    ];
    final settings = await rows(
      'SELECT name, value FROM user_settings WHERE name NOT LIKE \'tasting_audio_data_v1_%\'',
    );
    final attempts = <Map<String, Object?>>[];
    final warnings = <String>[];
    {
      for (final row in settings) {
        final name = row['name']! as String;
        if (name != DiplomaResearchRepository.settingKey &&
            !prefixes.any(name.startsWith)) {
          continue;
        }
        if (tastingId != null &&
            name !=
                '${GuidedTastingRepository.recordPrefix}${tastingId.replaceAll('-', '_')}') {
          continue;
        }
        try {
          final value = jsonDecode(row['value']! as String);
          if (value is! Map) throw const FormatException();
          Map<String, Object?>? summary;
          if (name.startsWith(RehearsalRepository.attemptPrefix)) {
            final attempt = RehearsalAttempt.fromJson(
              Map<String, dynamic>.from(value),
            );
            summary = {
              'status': attempt.isFinished
                  ? attempt.abandoned
                        ? 'abandoned'
                        : 'finished'
                  : 'in_progress',
              'mcq_correct': attempt.mcqCorrect,
              'mcq_total': attempt.mcqs.length,
              'grading_scope':
                  'Original app MCQs only. Written responses require review.',
            };
          } else if (name.startsWith(CmsRehearsalRepository.attemptPrefix)) {
            final attempt = CmsRehearsalAttempt.fromJson(
              Map<String, dynamic>.from(value),
            );
            summary = {
              'status': attempt.isFinished
                  ? attempt.isAbandoned
                        ? 'abandoned'
                        : 'finished'
                  : 'in_progress',
              'mcq_correct': attempt.mcqCorrect,
              'mcq_total': attempt.mcqs.length,
              'grading_scope': 'Original app MCQs only. Written/service/tasting responses require review.',
            };
          }
          attempts.add({
            'record_key': name,
            'practice_result': ?summary,
            'saved_record': value,
          });
        } catch (_) {
          // Preserve corrupt records explicitly, never invent a result.
          attempts.add({
            'record_key': name,
            'unreadable': true,
            'raw_saved_value': row['value'],
          });
          warnings.add(
            'Saved record $name is unreadable; included verbatim for recovery.',
          );
        }
      }
    }
    final recordings = <Map<String, Object?>>[];
    if (includeAudio) {
      for (final row in settings) {
        final name = row['name']! as String;
        if (!name.startsWith(TastingAudioStore.metaPrefix)) continue;
        final audio = TastingAudioStore.parse(name, row['value']! as String);
        if (tastingId != null && audio.sessionId != tastingId) continue;
        final bytes = await TastingAudioStore(db).read(audio);
        recordings.add({
          ...audio.toJson(),
          'archive_path': 'audio/${audio.id}.${audio.extension}',
          'bytes_base64': base64Encode(bytes),
        });
      }
    }
    return {
      'format': 'sommelier-review-report',
      'format_version': 1,
      'exported_at': utcNow(clock).toIso8601String(),
      'curriculum_release': release?.version,
      'notice': notice,
      'scope': tastingId == null
          ? 'All saved practice and tastings'
          : 'One tasting',
      'tasting_sessions': sessions,
      'tasting_answers': descriptors,
      'review_events': reviews,
      'presented_options': options,
      'practice_attempts': attempts,
      'recordings': recordings,
      'warnings': warnings,
    };
  });

  static String csvCell(Object? value) {
    var text = value?.toString() ?? '';
    // Protect spreadsheet applications against formulas in learner text.
    if (RegExp(r'^\s*[=+@\-\t\r]').hasMatch(text)) text = "'$text";
    return '"${text.replaceAll('"', '""')}"';
  }

  static String csv(List<Map<String, Object?>> rows) {
    final columns = {for (final row in rows) ...row.keys}.toList();
    if (columns.isEmpty) return '';
    return '${columns.map(csvCell).join(',')}\r\n${rows.map((r) => columns.map((c) => csvCell(r[c])).join(',')).join('\r\n')}\r\n';
  }

  static String _html(Object? value) =>
      const HtmlEscape().convert(value?.toString() ?? '');
  static String _render(Object? value) {
    if (value is Map) {
      return '<dl>${value.entries.map((e) => '<dt>${_html(e.key)}</dt><dd>${_render(e.value)}</dd>').join()}</dl>';
    }
    if (value is List) {
      return '<ol>${value.map((v) => '<li>${_render(v)}</li>').join()}</ol>';
    }
    return '<span>${_html(value)}</span>';
  }

  static String html(Map<String, Object?> report) =>
      '<!doctype html><html lang="en"><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'; media-src \'self\'">'
      '<title>Sommelier practice review</title><style>body{font:16px system-ui;max-width:1000px;margin:2em auto;padding:0 1em}dt{font-weight:bold}dd{margin:0 0 1em;white-space:pre-wrap;overflow-wrap:anywhere}li{margin-bottom:1em}audio{max-width:100%}@media print{audio{display:none}}</style>'
      '<h1>Sommelier practice review</h1><p>${_html(report['notice'])}</p>'
      '<p>Exported ${_html(report['exported_at'])}. Curriculum ${_html(report['curriculum_release'])}.</p>'
      '${['scope', 'warnings', 'review_events', 'presented_options', 'practice_attempts', 'tasting_sessions', 'tasting_answers'].map((k) => '<h2>${_html(k.replaceAll('_', ' '))}</h2>${_render(report[k])}').join()}'
      '<h2>Audio notes</h2>${(report['recordings'] as List).map((v) {
        final a = v as Map;
        return '<p>${_html(a['title'])}</p><audio controls src="${_html(a['archive_path'])}"></audio><p>${_html(a['archive_path'])}</p>';
      }).join()}'
      '<p>Open this file in a browser. Use Print to save a PDF for your reviewer. No network connection is required.</p></html>';

  Future<Uint8List> archive({
    bool includeAudio = false,
    String? tastingId,
  }) async {
    final report = await snapshot(
      includeAudio: includeAudio,
      tastingId: tastingId,
    );
    final package = Archive();
    var total = 0;
    final hashes = <String, String>{};
    void add(String name, List<int> bytes) {
      total += bytes.length;
      if (total > maxExportBytes) {
        throw StateError(
          'The report exceeds 64 MiB. Export individual tastings or omit audio. No records were silently excluded.',
        );
      }
      package.addFile(ArchiveFile(name, bytes.length, bytes));
      hashes[name] = sha256.convert(bytes).toString();
    }

    for (final value in report['recordings'] as List) {
      final audio = value as Map<String, Object?>;
      add(
        audio['archive_path']! as String,
        base64Decode(audio.remove('bytes_base64')! as String),
      );
    }
    add(
      'report.json',
      utf8.encode(const JsonEncoder.withIndent('  ').convert(report)),
    );
    add('report.html', utf8.encode(html(report)));
    for (final key in [
      'review_events',
      'tasting_sessions',
      'tasting_answers',
    ]) {
      add(
        '$key.csv',
        utf8.encode(csv((report[key] as List).cast<Map<String, Object?>>())),
      );
    }
    add(
      'README.txt',
      utf8.encode(
        'Extract this ZIP on any platform. Open report.html to read or print to PDF. '
        'CSV files open in spreadsheet apps; report.json retains saved question/answer and self-review snapshots. '
        'Audio files keep their original M4A, WebM, Ogg or WAV container; playback depends on the receiving device codecs. '
        'This is a review report, not a restorable private backup. Only share the records you wish your reviewer to see.\n\n$notice',
      ),
    );
    package.addFile(
      ArchiveFile.string(
        'sha256-manifest.json',
        const JsonEncoder.withIndent('  ').convert(hashes),
      ),
    );
    return Uint8List.fromList(ZipEncoder().encode(package));
  }
}
