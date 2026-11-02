import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/models.dart';
import '../state/providers.dart';

/// The port meter's words for a page that shows them, as the web's lib/live.js reads them: the
/// panel writes its last word and what it found without WebSocket deltas, so they are read from
/// its whole state every 2 s while the page is on the screen — not while its section is hidden,
/// and at once when the meter stops, so its outcome follows the switch without a gap.
mixin MeterPoll<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  static const every = Duration(seconds: 2);

  ({String status, double hz})? _reading;
  Timer? _poll;
  bool _asking = false;

  /// The meter's last word and what it found: as last read, or as the last whole state had them.
  ({String status, double hz}) meterReading(SpeakerState s) =>
      _reading ?? (status: s.meterStatus, hz: s.meterHz);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shown = TickerMode.valuesOf(context).enabled;
    if (shown && _poll == null) {
      unawaited(readMeter());
      _poll = Timer.periodic(every, (_) => unawaited(readMeter()));
    } else if (!shown) {
      _poll?.cancel();
      _poll = null;
    }
  }

  /// Reads the meter's words now; one request at a time, a failure left to the next tick.
  Future<void> readMeter() async {
    if (_asking) return;
    _asking = true;
    try {
      final reading = await ref.read(deviceApiProvider).portMeterReading();
      if (mounted) setState(() => _reading = reading);
    } on Object {
      // the next tick asks again
    } finally {
      _asking = false;
    }
  }

  /// Call from build: the meter stopping is read at once.
  void followMeter() => ref.listen(
    snapshotProvider.select((s) => s.speakers.measuring),
    (was, now) {
      if (was == true && now == false) unawaited(readMeter());
    },
  );

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
