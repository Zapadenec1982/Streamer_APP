import 'dart:async';

import 'package:flutter/foundation.dart';

import '../device/device_api.dart';
import '../device/eq.dart';

/// One editing session of the EQ, as the web's lib/eq.js has it. The panel keeps one document for
/// both editors — the glass's EQ page and this — with a revision that moves on every change; an
/// edit names the revision it was made from, and one the panel moved meanwhile is answered 409:
/// the page reads the panel's version rather than write over that change ([onConflict]).
///
/// [doc] is the document as the panel last said, with this page's own edits on top. Edits go one
/// at a time, newest wins: a drag makes dozens a second, and only the set the finger is at when
/// the previous request comes back is worth sending. The panel writes the file a minute after the
/// last edit, or at once when the page is left ([keep]).
class EqEditor {
  EqEditor(this._api, {this.onConflict, this.onError});

  final DeviceApi _api;
  final void Function()? onConflict;

  /// Anything else that failed: the request is not repeated.
  final void Function(Object error)? onError;

  final doc = ValueNotifier<EqDoc?>(null);

  /// The panel's revision this page's view is from.
  int _rev = 0;

  /// Bands waiting to go.
  List<EqBand>? _pending;

  /// Requests queued or in flight.
  int _busy = 0;

  /// Something was sent since the last keep.
  bool _edited = false;

  /// A keep asked for while requests were on their way.
  bool _keepAfter = false;

  /// The last revision of the panel's followed.
  int _seen = 0;
  Future<void> _chain = Future.value();
  bool _closed = false;

  /// An edit of this page's is on its way, or waits.
  bool get busy => _busy != 0 || _pending != null;

  Future<void> _enqueue(Future<void> Function() step) {
    _busy++;
    return _chain = _chain
        .then((_) => step())
        .catchError((Object e) async {
          _pending = null;
          if (e is EqChanged) {
            await _reload().catchError((Object _) {});
            if (!_closed) onConflict?.call();
          } else if (!_closed) {
            onError?.call(e);
          }
        })
        .whenComplete(() {
          _busy--;
          if (_busy == 0 && _keepAfter) _keepNow();
        });
  }

  /// Everything sent has landed: the panel writes it at once. The keep names no revision.
  void _keepNow() {
    _keepAfter = false;
    if (!_edited) return;
    _edited = false;
    unawaited(_api.keepSound().catchError((Object _) {}));
  }

  Future<void> _reload() async {
    final d = await _api.eq();
    _rev = d.rev;
    if (!_closed) doc.value = d;
  }

  Future<void> _sendPending() async {
    final bands = _pending;
    _pending = null;
    if (bands == null) return;
    _rev = await _api.setEqBands(_rev, bands);
    _edited = true;
    final d = doc.value;
    if (d != null && !_closed) doc.value = d.copyWith(rev: _rev);
  }

  Future<void> load() => _enqueue(_reload);

  /// Section 0's bands, set by hand: the sound is «Власний» (eq_presets.h).
  void setBands(List<EqBand> bands) {
    final clean = [for (final b in bands) b.clamped()];
    final d = doc.value;
    if (d != null) doc.value = d.copyWith(bands: clean, preset: 'custom');
    final queued = _pending != null;
    _pending = clean;
    if (!queued) unawaited(_enqueue(_sendPending));
  }

  /// A sound by id; "custom" brings the person's own set back. Made on the panel's version, as the
  /// Sound sheet makes it ([DeviceApi.chooseSound]): a choice is not an edit to merge.
  Future<void> choose(String id) {
    final d = doc.value;
    if (d == null || d.preset == id) return _chain;
    doc.value = d.copyWith(preset: id);
    return _enqueue(() async {
      await _api.chooseSound(id);
      _edited = true;
      // the panel built the bands
      await _reload();
    });
  }

  /// The panel moved the document (audio.eq_rev): take its version. Not while an edit of this
  /// page's is on its way — the next change looks again — and once per revision, since a change
  /// can still carry the one before this page's own last edit.
  void follow(int deviceRev) {
    if (deviceRev == 0 || deviceRev == _rev || deviceRev == _seen) return;
    if (busy) return;
    _seen = deviceRev;
    unawaited(_enqueue(_reload));
  }

  /// The page is left or hidden: the panel writes what it has at once. Not before the requests on
  /// their way have landed: bands still waiting would go with the revision from before the one in
  /// flight, and the panel refuses that (409). They go in turn, and the keep after them.
  void keep() {
    if (_busy != 0) {
      _keepAfter = true;
    } else {
      _keepNow();
    }
  }

  /// The page is gone: what is on its way still lands and is kept; nothing is said any more.
  void close() {
    keep();
    _closed = true;
    doc.dispose();
  }
}
