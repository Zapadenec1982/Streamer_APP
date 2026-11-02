import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../device/device_api.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'link_state.dart';
import 'sound_sheet.dart';

/// Налаштування › Звук › Тембр і гучність, as the web's system/SoundPage.svelte: the sounds, the
/// timbre and the equalizer, of which the Player's sheet is the top; then the volume's two and
/// the leveler by the clock. A sound chosen here is written as the page closes.
class SoundPage extends ConsumerStatefulWidget {
  const SoundPage({super.key});

  @override
  ConsumerState<SoundPage> createState() => _SoundPageState();
}

class _SoundPageState extends ConsumerState<SoundPage> {
  late final DeviceApi _api;

  @override
  void initState() {
    super.initState();
    // kept for dispose(), where ref is no longer the page's
    _api = ref.read(deviceApiProvider);
  }

  @override
  void dispose() {
    _api.keepSound().catchError((Object _) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.sysTimbreVolume)),
      body: PanelPage(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            SoundControls(
              page: true,
              onEq: () => context.go('/settings/sound/eq'),
            ),
          ],
        ),
      ),
    );
  }
}
