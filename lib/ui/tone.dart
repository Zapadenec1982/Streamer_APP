import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device_api.dart';
import '../device/models.dart';
import '../device/speakers.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'labels.dart';
import 'writes.dart';

/// The test tone as the port's search by hand drives it, as the web's lib/tone.js: the source that
/// played before the first tone is remembered, for the last step to bring back ("джерело — як
/// було"); a source chosen since the tone stopped is the person's, and is left alone.
class ToneSession {
  SourceId? _before;

  /// Plays the tone at [hz] through the DSP; [portOff] and [volCap] ride with it.
  Future<void> play(
    DeviceApi api, {
    required int hz,
    bool portOff = false,
    int? volCap,
  }) {
    _remember(api.current.now.source);
    return api.playTone(hz: hz, portOff: portOff, volCap: volCap);
  }

  void _remember(SourceId source) {
    if (source == SourceId.tone ||
        (source == SourceId.off && _before != null)) {
      return;
    }
    _before = source;
  }

  /// Stops the tone. [restore] brings back the source from before it; otherwise the source goes
  /// off. [write] rides in the same body — what the search found.
  Future<void> stop(
    DeviceApi api, {
    bool restore = false,
    SpeakerWrite? write,
  }) async {
    final source = api.current.now.source;
    final playing = api.current.tone.on;
    final before = _before;
    final SourceId? then;
    if (restore &&
        before != null &&
        before != SourceId.tone &&
        (playing || source == SourceId.off)) {
      then = before;
    } else if (playing) {
      then = SourceId.off;
    } else {
      then = null;
    }
    await api.stopTone(then: then, write: write);
    if (restore) _before = null;
  }
}

final toneSessionProvider = Provider<ToneSession>((ref) {
  // a session per streamer: another streamer's source is not this one's to bring back
  ref.watch(deviceApiProvider);
  return ToneSession();
});

/// What the test tone is doing, over the navigation on every page — a tone left playing on the way
/// out of the search, or started by another client, shows wherever one is — and the button that
/// stops it now, as the web's ToneBar. A calibration tone (past the DSP) says how long until the
/// streamer turns it off by itself; one through the DSP stops after two idle minutes.
class ToneBar extends ConsumerStatefulWidget {
  const ToneBar({super.key, required this.tone});

  final ToneState tone;

  @override
  ConsumerState<ToneBar> createState() => _ToneBarState();
}

class _ToneBarState extends ConsumerState<ToneBar> {
  /// Since when a calibration tone has played, and whether this bar saw it start.
  DateTime? _since;
  bool _exact = false;
  Timer? _clock;

  bool get _cal => widget.tone.on && widget.tone.mode != ToneMode.chain;

  @override
  void initState() {
    super.initState();
    // one already playing when the bar first looked: its start is not known
    _track(exact: false);
  }

  @override
  void didUpdateWidget(ToneBar old) {
    super.didUpdateWidget(old);
    _track(exact: true);
  }

  void _track({required bool exact}) {
    if (_cal && _since == null) {
      _since = DateTime.now();
      _exact = exact;
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!_cal && _since != null) {
      _since = null;
      _clock?.cancel();
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final tone = widget.tone;
    final channel = switch (tone.channel) {
      ToneChannel.left => l.calChLeft,
      ToneChannel.right => l.calChRight,
      ToneChannel.both => l.calChBoth,
    };
    final what = _cal
        ? [
            '${tone.hz} ${l.unitHz}',
            '${l.decimal(tone.db10 / 10, 1)} ${l.unitDbfs}',
            channel,
          ].join(' · ')
        : '${tone.hz} ${l.unitHz} · ${l.calToneChain}';
    final max = ToneState.calMax.inSeconds;
    final since = _since;
    final until = !_cal
        ? ''
        : _exact && since != null
        ? l.calToneLeft(
            '${(max - DateTime.now().difference(since).inSeconds).clamp(0, max)}',
          )
        : l.calToneMax('$max');
    return Semantics(
      liveRegion: true,
      child: Material(
        color: colors.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(Icons.graphic_eq, color: colors.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        l.calToneOn,
                        until,
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: text.titleSmall?.copyWith(
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    Text(
                      what,
                      style: text.bodyMedium?.copyWith(
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              // a square, not a word: the bar's words keep the width at a large text size
              IconButton.filledTonal(
                tooltip: l.calToneStop,
                onPressed: () => act(
                  context,
                  ref,
                  (api) => ref.read(toneSessionProvider).stop(api),
                ),
                icon: const Icon(Icons.stop),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
