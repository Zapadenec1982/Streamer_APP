import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../device/models.dart';
import '../device/panels.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'bt_page.dart';
import 'labels.dart';
import 'tone.dart';
import 'writes.dart';

/// The three sections, in the order and with the icons of the panel's drawer and the web's bar,
/// and over them, away from the Player, the mini-player.
class Shell extends ConsumerWidget {
  const Shell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final now = ref.watch(snapshotProvider.select((s) => s.now));
    final known = ref.watch(snapshotProvider.select((s) => s.known));
    final tone = ref.watch(snapshotProvider.select((s) => s.tone));
    // The web's rule (Shell.svelte): what plays, or what a tap could resume; never on the Player,
    // which is the player itself.
    final mini =
        navigationShell.currentIndex != 0 &&
        known &&
        ref.watch(activePanelProvider) is! NoPanel &&
        (now.playing || (now.canToggle && now.live));
    return Scaffold(
      // a phone asking to pair is asked about over every page
      body: PairingWatcher(child: navigationShell),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // a test tone shows on every page, wherever it was started
          if (known && tone.on) ToneBar(tone: tone),
          if (mini) _MiniPlayer(now: now),
          NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (index) => navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            ),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.play_circle_outline),
                selectedIcon: const Icon(Icons.play_circle),
                label: l.navPlayer,
              ),
              NavigationDestination(
                icon: const Icon(Icons.speaker_group_outlined),
                selectedIcon: const Icon(Icons.speaker_group),
                label: l.navSource,
              ),
              NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings),
                label: l.navSettings,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What plays, small, over the navigation — the web's MiniPlayer: where it comes from, the title
/// and the line under it, and play or pause. A tap on it opens the Player. A station does not
/// pause: its button starts and stops the stream, as the knob's press does on the glass.
class _MiniPlayer extends ConsumerWidget {
  const _MiniPlayer({required this.now});

  final NowPlaying now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final stops = now.kind == NowKind.radio;
    final sub = now.subtitle == null ? '' : l.label(now.subtitle!);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Material(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        elevation: 3,
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: l.miniOpen,
                child: InkWell(
                  onTap: () => context.go('/player'),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(nowIcon(now.kind), color: colors.outline),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                l.label(now.title),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleSmall,
                              ),
                              if (sub.isNotEmpty)
                                Text(
                                  sub,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodyMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (now.canToggle && now.live)
              IconButton(
                tooltip: !now.playing
                    ? l.transportPlay
                    : stops
                    ? l.transportStop
                    : l.transportPause,
                onPressed: () => act(
                  context,
                  ref,
                  (api) => api.transport(TransportAction.toggle),
                ),
                icon: Icon(
                  !now.playing
                      ? Icons.play_arrow
                      : stops
                      ? Icons.stop
                      : Icons.pause,
                ),
              ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
