import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// «Скасувати» after a slider or a drag on the equalizer's graph moved a sound setting, as the
/// web's lib/undo.js has it: a snackbar for [shown], «Бас: 0 → +3».
///
/// One snackbar, for the setting moved last. The same setting moved again while it shows keeps
/// where it started; moved back there, the snackbar goes. Its action puts the start back. Taps —
/// buttons, switches — have none: what one did was meant.
class UndoNotes {
  UndoNotes({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const shown = Duration(seconds: 5);

  final DateTime Function() _now;

  /// The snackbar up now: what it is for, where that started and when.
  ({Object key, Object? from, DateTime at})? _current;

  /// [key] moved from [from] to [to]; [text] words it, [revert] puts the start back. Values are
  /// compared with ==: a record of them compares field by field.
  void note<T>(
    BuildContext context, {
    required Object key,
    required T from,
    required T to,
    required String action,
    required String Function(T from, T to) text,
    required void Function(T from) revert,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final now = _now();
    var start = from;
    final current = _current;
    // still up: it goes, and the same setting keeps where it started
    final up = current != null && now.difference(current.at) < shown;
    if (up && current.key == key) start = current.from as T;
    if (up) messenger.hideCurrentSnackBar();
    _current = null;
    if (start == to) return;
    final entry = (key: key, from: start, at: now);
    _current = entry;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(text(start, to)),
          duration: shown,
          action: SnackBarAction(
            label: action,
            onPressed: () {
              if (_current == entry) _current = null;
              revert(start);
            },
          ),
        ),
      );
  }
}

final undoProvider = Provider<UndoNotes>((ref) => UndoNotes());
