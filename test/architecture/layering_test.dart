import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The layering of docs/architecture/architecture-validation.md §3.1, as
/// recorded in architecture audit DL-1: screens and providers reach the
/// database only through the repositories in `lib/core`, and `lib/core`
/// holds no widgets.
void main() {
  Iterable<(String, int, String)> linesOf(String directory) sync* {
    final files =
        Directory(directory)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        yield (file.path, i + 1, lines[i]);
      }
    }
  }

  test('only lib/core queries the database', () {
    // Drift's query entry points, called on a database or a table.
    final query = RegExp(
      r'\b(customSelect|customStatement|customUpdate|customInsert|batch|'
      r'transaction)\(|\b(db|database)\.(select|into|update|delete)\(',
    );
    final offending = [
      for (final directory in ['lib/app', 'lib/features'])
        for (final (path, line, text) in linesOf(directory))
          if (query.hasMatch(text)) '$path:$line: ${text.trim()}',
    ];
    expect(offending, isEmpty, reason: 'move these queries into lib/core');
  });

  test('lib/core holds no widgets', () {
    final ui = RegExp(
      r"import 'package:flutter/(material|widgets|cupertino)\.dart'",
    );
    final offending = [
      for (final (path, line, text) in linesOf('lib/core'))
        if (ui.hasMatch(text)) '$path:$line: ${text.trim()}',
    ];
    expect(offending, isEmpty);
  });

  test('lib/core is plain Dart outside its providers', () {
    // The curriculum tools run lib/core with `dart run`, without Flutter, and
    // geography §8 keeps the geometry core pure. Only the Riverpod providers
    // (*_providers.dart) and the on-device database connection need Flutter.
    final flutter = RegExp(
      r"import 'package:(flutter|flutter_riverpod|drift_flutter)/|"
      r"import 'dart:ui'",
    );
    bool mayUseFlutter(String path) {
      final name = path.replaceAll(r'\', '/').split('/').last;
      return name.endsWith('_providers.dart') ||
          name == 'database_connection.dart';
    }

    final offending = [
      for (final (path, line, text) in linesOf('lib/core'))
        if (!mayUseFlutter(path) && flutter.hasMatch(text))
          '$path:$line: ${text.trim()}',
    ];
    expect(offending, isEmpty);
  });

  test('the check sees a query when there is one', () {
    final query = RegExp(r'\b(db|database)\.(select|into|update|delete)\(');
    expect(
      query.hasMatch('final rows = db.select(db.questions).get();'),
      isTrue,
    );
    expect(
      query.hasMatch('ref.read(learnerProfilesProvider).selectTrack(id);'),
      isFalse,
    );
  });
}
