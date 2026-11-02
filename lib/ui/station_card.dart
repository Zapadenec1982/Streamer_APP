import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../device/models.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'station_badge.dart';
import 'writes.dart';

/// The station list as last read (`GET /api/stations`), read again whenever its generation moves
/// (`radio.list_rev`) — by a store here, on the glass or in the web.
final stationListProvider = FutureProvider<StationList>((ref) {
  ref.watch(snapshotProvider.select((s) => s.radio.listRev));
  return ref.watch(deviceApiProvider).stations();
});

/// The station's name between ‹ and ›, the glass's station face (the web's Player station card);
/// ♥ keeps a catalog station that is not in the list yet.
class StationTitle extends ConsumerWidget {
  const StationTitle({super.key, required this.name, required this.now});

  final String name;
  final NowPlaying now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final radio = ref.watch(snapshotProvider.select((s) => s.radio));
    return Row(
      children: [
        IconButton(
          tooltip: l.transportPrev,
          onPressed: now.canPrevious
              ? () => act(
                  context,
                  ref,
                  (api) => api.transport(TransportAction.previous),
                )
              : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            name,
            style: Theme.of(context).textTheme.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
        if (radio.keepable)
          IconButton(
            tooltip: l.manageKeep,
            onPressed: () async {
              await act(context, ref, (api) => api.keepStation());
              if (context.mounted) _say(context, l.manageKept);
            },
            icon: const Icon(Icons.favorite_border),
          ),
        IconButton(
          tooltip: l.transportNext,
          onPressed: now.canNext
              ? () => act(
                  context,
                  ref,
                  (api) => api.transport(TransportAction.next),
                )
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

/// The six presets, 3×2, with the glass's rules: a tap tunes, a hold stores what plays, a tap on
/// an empty one stores too. Then the way to every station.
class StationPresets extends ConsumerWidget {
  const StationPresets({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final radio = ref.watch(snapshotProvider.select((s) => s.radio));
    final list = ref.watch(stationListProvider).value;
    Future<void> store(int slot) async {
      HapticFeedback.mediumImpact();
      final name = ref.read(snapshotProvider).now.title;
      await act(context, ref, (api) => api.storePreset(slot));
      if (context.mounted && name is TextLabel) {
        _say(context, l.catInPreset('${slot + 1}', name.text));
      }
    }

    return Column(
      children: [
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: _Preset.height(context),
          ),
          children: [
            for (var slot = 0; slot < StationList.presetCount; slot++)
              _Preset(
                slot: slot,
                station: switch (list?.presets[slot]) {
                  final int i? when i >= 0 => list!.stations[i],
                  _ => null,
                },
                on:
                    list != null &&
                    list.presets[slot] >= 0 &&
                    list.presets[slot] == radio.current,
                storable: radio.storable,
                onTap: list == null
                    ? null
                    : list.presets[slot] >= 0
                    ? () => act(
                        context,
                        ref,
                        (api) => api.listen(list.presets[slot]),
                      )
                    : radio.storable
                    ? () => store(slot)
                    : null,
                onHold: list != null && radio.storable
                    ? () => store(slot)
                    : null,
              ),
          ],
        ),
        if (radio.count > 0)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => context.go('/player/stations'),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.chevron_right),
              label: Text(l.stAll('${radio.count}')),
            ),
          ),
      ],
    );
  }
}

class _Preset extends StatelessWidget {
  const _Preset({
    required this.slot,
    required this.station,
    required this.on,
    required this.storable,
    required this.onTap,
    required this.onHold,
  });

  final int slot;
  final Station? station;
  final bool on;
  final bool storable;
  final VoidCallback? onTap;
  final VoidCallback? onHold;

  /// Two lines of the name at the phone's text size, and never under the 56 dp a finger needs.
  static double height(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    final line =
        MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 12) *
        (style?.height ?? 1.34);
    return (2 * line + 16).clamp(56, double.infinity);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final st = station;
    return Material(
      color: on ? colors.primaryContainer : colors.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: on
            ? BorderSide(color: colors.primary, width: 2)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onHold,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              if (st != null)
                StationDisc(name: st.name, size: 28)
              else
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Text('${slot + 1}', style: text.labelMedium),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  st?.name ?? (storable ? l.stPresetStore : l.stPresetEmpty),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium?.copyWith(
                    color: st == null ? colors.onSurfaceVariant : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The station's disc: its stand-in for a logo.
class StationDisc extends StatelessWidget {
  const StationDisc({
    super.key,
    required this.name,
    required this.size,
    this.label = false,
  });

  final String name;
  final double size;

  /// The whole label (the tile), rather than its first character (a preset).
  final bool label;

  @override
  Widget build(BuildContext context) {
    final badge = StationBadge.of(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF000000 | badge.color),
      ),
      child: FittedBox(
        child: Padding(
          padding: EdgeInsets.all(size * 0.18),
          child: Text(
            label ? badge.label : badge.first,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: size * 0.45,
            ),
          ),
        ),
      ),
    );
  }
}

void _say(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..clearSnackBars()
  ..showSnackBar(SnackBar(content: Text(text)));
