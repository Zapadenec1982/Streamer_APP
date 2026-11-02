import 'dart:async';

/// A value moved by hand — a slider, the phone's volume buttons — and written to the panel as the
/// web writes a live one (createSettingSender in the firmware's webui/src/lib/settings.js):
///
/// - the first value of a run goes at once, then the newest at most every [every];
/// - never two writes at a time: a value that comes while one is on its way goes after it, so the
///   panel takes them in the order they were made, and the last one made is the last it takes;
/// - [shows] is the hand's value while the hand is on it, and after it lets go until the panel
///   reports the last value written — or [patience] passes, or a write is refused — so the control
///   never steps back to a value the panel has already left behind.
class SettingSender {
  SettingSender(
    this._write, {
    this.onSettled,
    this.every = const Duration(milliseconds: 150),
    this.patience = const Duration(seconds: 2),
  });

  /// Writes a value; true when the panel took it.
  final Future<bool> Function(int value) _write;

  /// The hand's value has given way to the panel's.
  final void Function()? onSettled;
  final Duration every;
  final Duration patience;

  int? _wanted;
  int? _held;
  bool _inFlight = false;
  bool _down = false;
  bool _disposed = false;
  Timer? _slot;
  Timer? _giveUp;

  /// The value to show, given the one the panel reports.
  int shows(int reported) => _wanted ?? reported;

  /// The hand's value, while it is still the one shown.
  int? get wanted => _wanted;

  /// A value from the hand; the one it already asked for writes nothing more.
  void send(int value) {
    _down = true;
    _giveUp?.cancel();
    if (value == _wanted) return;
    _wanted = value;
    _held = value;
    if (_slot == null) _next();
  }

  /// The hand lets go. What is held goes in its turn.
  void release() {
    _down = false;
    _giveUp?.cancel();
    _giveUp = Timer(patience, _settle);
  }

  /// The panel reported [value]: the last one written, with nothing more to go, ends the run.
  void heard(int value) {
    if (!_down && !_inFlight && _held == null && value == _wanted) _settle();
  }

  void dispose() {
    _disposed = true;
    _slot?.cancel();
    _giveUp?.cancel();
  }

  /// A slot: the newest goes now — unless one is on its way, and then it goes when that lands.
  void _next() {
    _slot = null;
    final value = _held;
    if (value == null || _inFlight || _disposed) return;
    _held = null;
    unawaited(_post(value));
    _slot = Timer(every, _next);
  }

  Future<void> _post(int value) async {
    _inFlight = true;
    final took = await _write(value);
    _inFlight = false;
    if (_disposed) return;
    // refused: the panel's own value is the one to show
    if (!took && _held == null) _settle();
    final next = _held;
    if (next != null && _slot == null) {
      _held = null;
      unawaited(_post(next));
    }
  }

  void _settle() {
    _giveUp?.cancel();
    if (_wanted == null || _disposed) return;
    _wanted = null;
    onSettled?.call();
  }
}
