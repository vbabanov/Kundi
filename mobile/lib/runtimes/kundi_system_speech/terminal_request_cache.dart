/// Recent terminal metadata only. Admission always requires a current request,
/// so evicting an old ID can never re-admit its late callbacks.
final class TerminalRequestCache<T> {
  TerminalRequestCache({this.capacity = 128}) : assert(capacity > 0);
  final int capacity;
  final _entries = <String, T>{}; // Dart map literals preserve insertion order.
  int get length => _entries.length;
  T? operator [](String id) => _entries[id];
  bool contains(String id) => _entries.containsKey(id);
  void add(String id, T value) {
    if (id.isEmpty || _entries.containsKey(id)) return;
    _entries[id] = value;
    if (_entries.length > capacity) _entries.remove(_entries.keys.first);
  }

  void clear() => _entries.clear();
}
