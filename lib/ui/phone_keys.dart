import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/panels.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'sender.dart';
import 'writes.dart';

/// The app's hold on the phone: in the background it lets go of the panel (its WebSocket slot)
/// and of the volume buttons; back on the screen it hears the panel again from its whole state.
/// While a panel is chosen the phone's volume buttons step the panel's volume (Android; iOS has
/// no such hook), and one popup over every page follows them.
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
  late final _sender = SettingSender(
    (value) => mounted
        ? act(context, ref, (api) => api.setVolume(value))
        : Future.value(false),
  );

  /// The volume the popup shows; null once it has gone.
  int? _popup;
  Timer? _hide;

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
    _sender.dispose();
    _hide?.cancel();
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

  /// Presses add up from the volume they asked for until the panel has reported it, so a quick
  /// run of them is not lost to the time the panel takes to report back; they reach the panel as
  /// the Player's slider does ([SettingSender]). The popup follows each press and goes 1.5 s after
  /// the last — one popup, not one queued behind another per press.
  void _press(int dir) {
    if (dir == 0) return;
    final from = _sender.shows(ref.read(snapshotProvider).volume);
    final to = (from + dir * PhoneBinding.step).clamp(0, 100);
    // each press is a whole gesture
    _sender
      ..send(to)
      ..release();
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _popup = null);
    });
    setState(() => _popup = to);
  }

  @override
  Widget build(BuildContext context) {
    // a panel chosen or dropped changes whose the buttons are
    ref.listen(activePanelProvider, (_, _) => _intercept());
    ref.listen(
      snapshotProvider.select((s) => s.volume),
      (_, reported) => _sender.heard(reported),
    );
    final volume = _popup;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        // over every page, a sheet or a dialog too, and never in a finger's way
        IgnorePointer(
          child: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: volume == null
                    ? const SizedBox.shrink()
                    : _VolumePopup(
                        key: const ValueKey('volume'),
                        volume: volume,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The volume the buttons have set: the panel's, not the phone's.
class _VolumePopup extends StatelessWidget {
  const _VolumePopup({super.key, required this.volume});

  final int volume;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      label: '${l.volumeLabel} $volume',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Material(
            color: theme.colorScheme.surfaceContainerHighest,
            elevation: 3,
            shape: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    volume == 0 ? Icons.volume_off : Icons.volume_up,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 160,
                    child: LinearProgressIndicator(value: volume / 100),
                  ),
                  const SizedBox(width: 12),
                  Text('$volume', style: theme.textTheme.titleSmall),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
