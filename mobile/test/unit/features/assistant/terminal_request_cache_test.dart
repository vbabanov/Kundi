import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/runtimes/kundi_system_speech/terminal_request_cache.dart';

void main() {
  test('terminal eviction is FIFO and duplicate insertion cannot refresh it',
      () {
    final cache = TerminalRequestCache<int>(capacity: 2);
    cache.add('a', 1);
    cache.add('b', 2);
    cache.add('a', 3);
    cache.add('c', 4);
    expect(cache.contains('a'), isFalse);
    expect(cache['b'], 2);
    expect(cache['c'], 4);
    expect(cache.length, 2);
    cache.clear();
    expect(cache.length, 0);
  });
}
