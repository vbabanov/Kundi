import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/runtimes/kundi_native_avatar/kundi_first_paint_notifier.dart';

void main() {
  testWidgets('reports mounted and real paint once for a generation',
      (tester) async {
    final mounted = <int>[];
    final painted = <int>[];

    await tester.pumpWidget(
      _candidate(
        generation: 1,
        onMounted: mounted.add,
        onPainted: painted.add,
      ),
    );

    expect(mounted, <int>[1]);
    expect(painted, <int>[1]);

    await tester.pumpWidget(
      _candidate(
        generation: 1,
        onMounted: mounted.add,
        onPainted: painted.add,
      ),
    );
    await tester.pump();

    expect(mounted, <int>[1]);
    expect(painted, <int>[1]);
  });

  testWidgets('new generation receives exactly one new paint callback',
      (tester) async {
    final mounted = <int>[];
    final painted = <int>[];

    await tester.pumpWidget(
      _candidate(
        generation: 1,
        onMounted: mounted.add,
        onPainted: painted.add,
      ),
    );
    await tester.pumpWidget(
      _candidate(
        generation: 2,
        onMounted: mounted.add,
        onPainted: painted.add,
      ),
    );

    expect(mounted, <int>[1, 2]);
    expect(painted, <int>[1, 2]);
  });

  testWidgets('dispose is safe and cannot emit another callback',
      (tester) async {
    final mounted = <int>[];
    final painted = <int>[];

    await tester.pumpWidget(
      _candidate(
        generation: 7,
        onMounted: mounted.add,
        onPainted: painted.add,
      ),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(mounted, <int>[7]);
    expect(painted, <int>[7]);
  });
}

Widget _candidate({
  required int generation,
  required ValueChanged<int> onMounted,
  required ValueChanged<int> onPainted,
}) =>
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 80,
          height: 80,
          child: KundiFirstPaintNotifier(
            generation: generation,
            onMounted: onMounted,
            onPainted: onPainted,
            child: const ColoredBox(color: Colors.purple),
          ),
        ),
      ),
    );
