import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device_api.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'sender.dart';
import 'undo.dart';
import 'writes.dart';

/// «+2», «0», «−2»: a tone's dB as the glass and the web say them.
String signedNumber(int v) => v > 0
    ? '+$v'
    : v < 0
    ? '−${-v}'
    : '0';

/// A sound setting on a slider: [min]…[max] in [step]s, moving under the finger at once and
/// written as the volume is ([SettingSender]). Once let go somewhere else, a snackbar offers to put
/// it back (undo.dart).
class StepSlider extends ConsumerStatefulWidget {
  const StepSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.step = 1,
    required this.format,
    required this.send,
    this.enabled = true,
    this.disabledText,
    this.ends,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final String Function(int value) format;
  final Future<void> Function(DeviceApi api, int value) send;

  /// Off, the slider is dimmed and says [disabledText] — what rules it now — instead of a value.
  final bool enabled;
  final String? disabledText;

  /// Words under the two ends of the track: «Л» and «П» for the balance.
  final (String, String)? ends;

  @override
  ConsumerState<StepSlider> createState() => _StepSliderState();
}

class _StepSliderState extends ConsumerState<StepSlider> {
  late final _sender = SettingSender(
    (value) => mounted
        ? act(context, ref, (api) => widget.send(api, value))
        : Future.value(false),
    onSettled: () {
      if (mounted) setState(() {});
    },
  );
  double? _dragging;
  int? _from;

  @override
  void didUpdateWidget(StepSlider old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value) _sender.heard(widget.value);
  }

  @override
  void dispose() {
    _sender.dispose();
    super.dispose();
  }

  int _on(double v) =>
      (widget.min + ((v - widget.min) / widget.step).round() * widget.step)
          .clamp(widget.min, widget.max);

  void _released(int from, int to) {
    final api = ref.read(deviceApiProvider);
    final l = AppLocalizations.of(context);
    ref
        .read(undoProvider)
        .note<int>(
          context,
          key: widget.label,
          from: from,
          to: to,
          action: l.undoAction,
          text: (a, b) =>
              '${widget.label}: ${widget.format(a)} → ${widget.format(b)}',
          revert: (a) {
            if (mounted) {
              _sender
                ..send(a)
                ..release();
              setState(() {});
            } else {
              unawaited(widget.send(api, a).catchError((Object _) {}));
            }
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final value = _dragging ?? _sender.shows(widget.value).toDouble();
    final shown = widget.enabled || widget.disabledText == null
        ? widget.format(_on(value))
        : widget.disabledText!;
    final ends = widget.ends;
    final small = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    // the name and the value over the slider, so neither wraps at the phone's text size; one node
    // for TalkBack — «Бас, +2» — that it moves a step at a time
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(child: Text(widget.label)),
                ExcludeSemantics(child: Text(shown)),
              ],
            ),
          ),
          Slider(
            value: value.clamp(widget.min.toDouble(), widget.max.toDouble()),
            min: widget.min.toDouble(),
            max: widget.max.toDouble(),
            divisions: (widget.max - widget.min) ~/ widget.step,
            label: shown,
            semanticFormatterCallback: (v) => widget.format(_on(v)),
            onChangeStart: (v) => _from = _on(v),
            onChanged: widget.enabled
                ? (v) {
                    setState(() => _dragging = v);
                    _sender.send(_on(v));
                  }
                : null,
            onChangeEnd: (v) {
              final to = _on(v);
              _sender
                ..send(to)
                ..release();
              setState(() => _dragging = null);
              final from = _from;
              _from = null;
              if (from != null && from != to) _released(from, to);
            },
          ),
          if (ends != null)
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(ends.$1, style: small),
                    Text(ends.$2, style: small),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
