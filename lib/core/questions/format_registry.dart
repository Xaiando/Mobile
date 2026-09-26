import 'exercise_format.dart';
import 'formats/flashcard/flashcard_format.dart';
import 'formats/map_identify/map_identify_format.dart';
import 'formats/map_locate/map_locate_format.dart';
import 'formats/mcq/mcq_format.dart';

/// The question formats, by ID (question-system §9). The validator, the
/// generator, the planner, the practice screen and the coverage checker all
/// read the same registry.
class FormatRegistry {
  /// Refuses a second format with the same ID.
  FormatRegistry(Iterable<ExerciseFormat> formats) {
    for (final format in formats) {
      if (_formats.containsKey(format.id)) {
        throw ArgumentError.value(
          format.id,
          'formats',
          'registers the format twice',
        );
      }
      _formats[format.id] = format;
    }
  }

  final _formats = <String, ExerciseFormat>{};

  ExerciseFormat? operator [](String id) => _formats[id];

  /// The format [id]; throws when none is registered.
  ExerciseFormat require(String id) =>
      _formats[id] ??
      (throw ArgumentError.value(id, 'id', 'is no registered format'));

  bool contains(String id) => _formats.containsKey(id);

  Iterable<String> get ids => _formats.keys;

  Iterable<ExerciseFormat> get formats => _formats.values;
}

/// The formats the app ships. A new format adds one line here, and its
/// view one line in `lib/features/practice/format_views.dart`.
final appFormats = FormatRegistry(const [
  FlashcardFormat(),
  McqFormat(),
  MapLocateFormat(),
  MapIdentifyFormat(),
]);
