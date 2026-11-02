import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/ui/sender.dart';

/// A value moved by hand reaches the panel as the web sends one: one write at a time, the newest
/// next, and the hand's value shown until the panel has it.
void main() {
  late List<int> writes;
  late List<Completer<bool>> landing;
  late SettingSender sender;

  setUp(() {
    writes = [];
    landing = [];
    sender = SettingSender((value) {
      writes.add(value);
      final done = Completer<bool>();
      landing.add(done);
      return done.future;
    });
  });
  tearDown(() => sender.dispose());

  testWidgets('never two writes at a time; the last value made goes last', (
    tester,
  ) async {
    sender
      ..send(10)
      ..send(20)
      ..send(30);
    await tester.pump(const Duration(milliseconds: 500));
    expect(writes, [10], reason: 'the others wait for the first to land');
    landing.last.complete(true);
    await tester.pump();
    expect(writes, [10, 30], reason: 'the newest, not each one between');
    landing.last.complete(true);
    await tester.pump(const Duration(seconds: 3));
    expect(writes, [10, 30]);
  });

  testWidgets('the hand\'s value stays shown until the panel reports it', (
    tester,
  ) async {
    sender
      ..send(40)
      ..release();
    // the panel still says where it was
    expect(sender.shows(32), 40);
    sender.heard(32);
    expect(sender.shows(32), 40);
    landing.last.complete(true);
    await tester.pump();
    sender.heard(40);
    expect(sender.wanted, isNull);
    expect(sender.shows(41), 41, reason: 'the panel again, from now on');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a refused value gives way to the panel\'s at once', (
    tester,
  ) async {
    sender
      ..send(50)
      ..release();
    landing.last.complete(false);
    await tester.pump();
    expect(sender.shows(45), 45);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a panel that never reports it: the hand\'s value goes after '
      'a while', (tester) async {
    sender
      ..send(60)
      ..release();
    landing.last.complete(true);
    await tester.pump(const Duration(seconds: 1));
    expect(sender.shows(55), 60);
    await tester.pump(const Duration(seconds: 2));
    expect(sender.shows(55), 55);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the same value again writes nothing more', (tester) async {
    sender
      ..send(70)
      ..send(70)
      ..release();
    landing.last.complete(true);
    await tester.pump(const Duration(seconds: 3));
    expect(writes, [70]);
  });
}
