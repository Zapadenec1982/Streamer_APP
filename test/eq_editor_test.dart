import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/device/eq.dart';
import 'package:streamer/device/panel/panel_link.dart';
import 'package:streamer/state/providers.dart';
import 'package:streamer/ui/eq_editor.dart';

/// The panel's EQ document as the editor meets it: each band write waits on [landing] until the
/// test lets it land, and the glass can move the document meanwhile ([glassEdits]).
class _Panel extends NoPanelApi {
  int rev = 5;
  String preset = 'rock';
  List<EqBand> bands = const [
    EqBand(type: EqType.peak, f: 100, gain: 3),
    EqBand(type: EqType.peak, f: 1000, gain: -2),
  ];
  final writes = <({int rev, List<EqBand> bands})>[];
  final landing = <Completer<void>>[];
  int reads = 0;
  int keeps = 0;
  Object? fail;

  void glassEdits() {
    rev++;
    bands = [bands.first.copyWith(gain: 6), ...bands.skip(1)];
  }

  @override
  Future<EqDoc> eq() async {
    reads++;
    return EqDoc(
      rev: rev,
      preset: preset,
      presets: const ['custom', 'flat', 'rock', 'jazz'],
      bands: bands,
    );
  }

  @override
  Future<int> setEqBands(int from, List<EqBand> set) async {
    writes.add((rev: from, bands: set));
    final done = Completer<void>();
    landing.add(done);
    await done.future;
    if (fail case final e?) throw e;
    if (from != rev) throw const EqChanged();
    bands = set;
    preset = 'custom';
    return ++rev;
  }

  @override
  Future<void> chooseSound(String id) async {
    preset = id;
    rev++;
  }

  @override
  Future<void> keepSound() async => keeps++;
}

void main() {
  late _Panel panel;
  late EqEditor editor;
  late int conflicts;
  late List<Object> errors;

  setUp(() async {
    panel = _Panel();
    conflicts = 0;
    errors = [];
    editor = EqEditor(
      panel,
      onConflict: () => conflicts++,
      onError: errors.add,
    );
    await editor.load();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  List<EqBand> moved(double gain) => [
    panel.bands.first.copyWith(gain: gain),
    ...panel.bands.skip(1),
  ];

  test('a drag\'s dozens of edits go one at a time: the first, then the '
      'newest when it comes back', () async {
    editor.setBands(moved(1));
    await settle();
    // the finger moves on while the first is on its way
    for (final g in [2.0, 3.0, 4.0]) {
      editor.setBands(moved(g));
    }
    expect(editor.doc.value!.bands.first.gain, 4, reason: 'shown at once');
    expect(editor.doc.value!.preset, 'custom');
    await settle();
    expect(panel.writes.map((w) => w.bands.first.gain), [1]);
    panel.landing.last.complete();
    await settle();
    await settle();
    expect(panel.writes.map((w) => w.bands.first.gain), [1, 4]);
    expect(
      panel.writes.last.rev,
      6,
      reason: 'from the revision the first made',
    );
    panel.landing.last.complete();
    await settle();
    expect(editor.busy, isFalse);
    expect(editor.doc.value!.rev, 7);
    expect(conflicts, 0);
  });

  test('an edit from a document the glass moved meanwhile does not write '
      'over it: the glass\'s version is shown, and said', () async {
    panel.glassEdits();
    editor.setBands(moved(-4));
    await settle();
    panel.landing.last.complete();
    await settle();
    await settle();
    expect(conflicts, 1);
    expect(editor.doc.value!.bands.first.gain, 6);
    expect(editor.doc.value!.rev, panel.rev);
    // and the next edit is made from it
    editor.setBands(moved(2));
    await settle();
    panel.landing.last.complete();
    await settle();
    expect(panel.bands.first.gain, 2);
    expect(conflicts, 1);
  });

  test('the glass\'s change is followed — not while an edit of the page\'s is '
      'on its way, and once for each revision', () async {
    final reads = panel.reads;
    editor.setBands(moved(1));
    panel.glassEdits();
    editor.follow(panel.rev);
    await settle();
    expect(panel.reads, reads, reason: 'its own edit is on its way');
    panel.landing.last.complete();
    await settle();
    await settle();
    // the edit was refused (the glass moved it) and the document read back
    expect(conflicts, 1);
    final after = panel.reads;
    panel.glassEdits();
    editor
      ..follow(panel.rev)
      ..follow(panel.rev);
    await settle();
    expect(panel.reads, after + 1);
    expect(editor.doc.value!.bands.first.gain, 6);
    editor.follow(panel.rev);
    await settle();
    expect(panel.reads, after + 1, reason: 'its own revision');
  });

  test('the page\'s own edit coming back over the socket before its reply '
      'does not put an older set over the finger\'s', () async {
    final reads = panel.reads;
    editor.setBands(moved(1));
    await settle();
    // the panel took it and says so (audio.eq_rev) before the reply is here
    editor.follow(panel.rev + 1);
    editor.setBands(moved(4));
    panel.landing.last.complete();
    await settle();
    await settle();
    panel.landing.last.complete();
    await settle();
    await settle();
    expect(panel.bands.first.gain, 4);
    expect(editor.doc.value!.bands.first.gain, 4);
    expect(panel.reads, reads);
  });

  test('leaving keeps: only when something was sent, and after what is on its '
      'way has landed', () async {
    editor.keep();
    await settle();
    expect(panel.keeps, 0, reason: 'nothing was sent');
    editor.setBands(moved(1));
    editor.keep();
    await settle();
    expect(panel.keeps, 0, reason: 'the edit is still on its way');
    panel.landing.last.complete();
    await settle();
    await settle();
    expect(panel.keeps, 1);
  });

  test('a sound is chosen on the panel and its bands read back', () async {
    final reads = panel.reads;
    await editor.choose('jazz');
    expect(panel.preset, 'jazz');
    expect(panel.reads, reads + 1);
    expect(editor.doc.value!.preset, 'jazz');
    await editor.choose('jazz');
    expect(panel.reads, reads + 1, reason: 'the one that plays');
  });

  test('a write refused for another reason is said, and the next edit goes '
      'from where the panel is', () async {
    panel.fail = const PanelError(500, 'internal');
    editor.setBands(moved(1));
    await settle();
    panel.landing.last.complete();
    await settle();
    expect(errors, [isA<PanelError>()]);
    expect(conflicts, 0);
    panel.fail = null;
    editor.setBands(moved(2));
    await settle();
    panel.landing.last.complete();
    await settle();
    expect(panel.bands.first.gain, 2);
  });

  test('a band is held to the panel\'s limits before it goes', () async {
    editor.setBands([
      const EqBand(type: EqType.lowshelf, f: 5, gain: 20, q: 3),
    ]);
    await settle();
    expect(
      panel.writes.last.bands.single,
      const EqBand(type: EqType.lowshelf, f: 20, gain: 12, q: 1),
    );
    panel.landing.last.complete();
  });
}
