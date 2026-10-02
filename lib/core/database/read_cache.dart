/// Remembers what read-only queries return during one pass over a database
/// that does not change meanwhile.
///
/// Question generation asks the same things again and again: the places that
/// contain a node, the nodes drawn inside a frame, for each template of an
/// item and for each item beside it. Answering each once cuts first-launch
/// ingestion several-fold without changing a result.
///
/// A cache lives for one pass and is then dropped. While it is in use,
/// nothing may write the rows it has read. It hands out what it stored, so a
/// caller must not change a returned list: store lists unmodifiable, so that
/// a mistake fails at once instead of corrupting later answers.
class ReadCache {
  ReadCache() : _remembers = true;

  /// A cache that remembers nothing: every [of] reads. Tests use it to show
  /// that remembering changes no result.
  ReadCache.passThrough() : _remembers = false;

  final bool _remembers;
  final _values = <Object, Object?>{};

  /// How many answers are remembered.
  int get length => _values.length;

  /// The value for [key]: from memory, or by running [read] and keeping what
  /// it returns. A key is a record or another value with structural
  /// equality, and must name everything [read] depends on.
  Future<T> of<T>(Object key, Future<T> Function() read) async {
    if (!_remembers) return read();
    if (_values.containsKey(key)) return _values[key] as T;
    final value = await read();
    _values[key] = value;
    return value;
  }
}
