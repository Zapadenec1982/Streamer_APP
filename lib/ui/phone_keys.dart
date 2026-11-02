import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/panels.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'writes.dart';

/// The app's hold on the phone: in the background it lets go of the panel (its WebSocket slot)
/// and of the volume buttons; back on the screen it hears the panel again from its whole state.
/// While a panel is chosen the phone's volume buttons step the panel's volume (Android; iOS has
/// no such hook).
class PhoneBinding extends ConsumerStatefulWidget {
  const PhoneBinding({super.key, required this.child});

  final Widget child;

  static const _keys = MethodChannel('streamer/volume_keys');
  static const _presses = EventChannel('streamer/volume_keys/presses');

  /// One press of a volume button, in percent.
  static const step = 2;

  @override
  ConsumerState<PhoneBinding> createState() => _PhoneBindingState();
}

class _PhoneBindingState extends ConsumerState<PhoneBinding> {
  late final AppLifecycleListener _life;
  StreamSubscription<Object?>? _sub;
  bool _shown = true;
  int? _target;
  Timer? _settle;
  Timer? _send;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(
      onHide: () {
        _shown = false;
        ref.read(deviceApiProvider).suspend();
        _intercept();
      },
      onShow: () {
        _shown = true;
        ref.read(deviceApiProvider).resume();
        _intercept();
      },
    );
    try {
      _sub = PhoneBinding._presses.receiveBroadcastStream().listen(
        (step) => _press(step is int ? step : 0),
        onError: (Object _) {},
      );
    } on MissingPluginException {
      // no volume buttons to hold here
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _intercept());
  }

  @override
  void dispose() {
    _life.dispose();
    _sub?.cancel();
    _settle?.cancel();
    _send?.cancel();
    super.dispose();
  }

  /// The buttons are the panel's while the app is shown and a panel is chosen.
  Future<void> _intercept() async {
    final on = _shown && ref.read(activePanelProvider) is! NoPanel;
    try {
      await PhoneBinding._keys.invokeMethod<void>('intercept', on);
    } on MissingPluginException {
      // not on this platform
    } on PlatformException {
      // nor here
    }
  }

  /// Presses add up from the volume the panel last reported, so a quick run of them is not lost
  /// to the 200 ms the panel takes to report back; the newest goes out at most every 150 ms.
  void _press(int dir) {
    if (dir == 0) return;
    final from = _target ?? ref.read(snapshotProvider).volume;
    final to = (from + dir * PhoneBinding.step).clamp(0, 100);
    _target = to;
    _settle?.cancel();
    _settle = Timer(const Duration(seconds: 1), () => _target = null);
    _send ??= Timer(const Duration(milliseconds: 150), _flush);
    _show(to);
  }

  void _flush() {
    _send = null;
    final to = _target;
    if (to != null && mounted) act(context, ref, (api) => api.setVolume(to));
  }

  void _show(int volume) {
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 1200),
          content: Row(
            children: [
              Text('${l.volumeLabel} $volume'),
              const SizedBox(width: 16),
              Expanded(child: LinearProgressIndicator(value: volume / 100)),
            ],
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    // a panel chosen or dropped changes whose the buttons are
    ref.listen(activePanelProvider, (_, _) => _intercept());
    return widget.child;
  }
}
