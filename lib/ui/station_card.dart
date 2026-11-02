import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../device/models.dart';
import '../l10n/app_localizations.dart';
import '../device/radio_browser.dart';
import '../state/providers.dart';
import 'fit.dart';
import 'station_badge.dart';
import 'writes.dart';

/// The station list as last read (`GET /api/stations`), read again whenever its generation moves
/// (`radio.list_rev`) — by a store here, on the glass or in the web.
final stationListProvider = FutureProvider<StationList>((ref) {
  ref.watch(snapshotProvider.select((s) => s.radio.listRev));
  return ref.watch(deviceApiProvider).stations();
});

/// The list's logos from Radio Browser by the stations' uuids: uuid → logo, '' for none. Without
/// the catalogue (no internet) there are none, and the discs stand in.
final stationLogosProvider = FutureProvider<Map<String, String>>((ref) async {
  final list = await ref.watch(stationListProvider.future);
  final uuids = [
    for (final s in list.stations)
      if (s.uuid.isNotEmpty) s.uuid,
  ];
  if (uuids.isEmpty) return const {};
  try {
    return await ref.watch(radioBrowserProvider).favicons(uuids);
  } on CatalogError {
    return const {};
  }
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
  const StationPresets({super.key, this.all = true});

  /// The way to every station under them — not on the stations' own page.
  final bool all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final radio = ref.watch(snapshotProvider.select((s) => s.radio));
    final stations = ref.watch(stationListProvider);
    final list = stations.value;
    Future<void> store(int slot) async {
      HapticFeedback.mediumImpact();
      final name = ref.read(snapshotProvider).now.title;
      await act(context, ref, (api) => api.storePreset(slot));
      if (context.mounted && name is TextLabel) {
        _say(context, l.catInPreset('${slot + 1}', name.text));
      }
    }

    // the list did not come: say so where the presets would be, with the way to ask again
    if (list == null && stations.hasError) {
      return Row(
        children: [
          Expanded(child: Text(l.stLoadFailed)),
          TextButton(
            onPressed: () => ref.invalidate(stationListProvider),
            child: Text(l.appRetry),
          ),
        ],
      );
    }
    Station? at(int slot) => switch (list?.presets[slot]) {
      final int i? when i >= 0 => list!.stations[i],
      _ => null,
    };
    // until the list comes the buttons show their numbers only, not «Порожньо»
    String name(int slot) =>
        list == null ? '' : at(slot)?.name ?? _Preset.empty(l, radio.storable);
    final names = [
      for (var slot = 0; slot < StationList.presetCount; slot++) name(slot),
    ];
    final logos = ref.watch(stationLogosProvider).value ?? const {};
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, box) => GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _Preset.columns(context, box.maxWidth, names),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: _Preset.height(context),
            ),
            children: [
              for (var slot = 0; slot < StationList.presetCount; slot++)
                _Preset(
                  slot: slot,
                  name: names[slot],
                  station: at(slot),
                  logo: logos[at(slot)?.uuid] ?? '',
                  on:
                      list != null &&
                      list.presets[slot] >= 0 &&
                      list.presets[slot] == radio.current,
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
        ),
        if (all && radio.count > 0)
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
    required this.name,
    required this.station,
    this.logo = '',
    required this.on,
    required this.onTap,
    required this.onHold,
  });

  final int slot;

  /// The station's logo, or ''.
  final String logo;

  /// What the button says: the station's name, or what an empty one is for.
  final String name;
  final Station? station;
  final bool on;
  final VoidCallback? onTap;
  final VoidCallback? onHold;

  static const _gap = 8.0;
  static const _disc = 28.0;

  static String empty(AppLocalizations l, bool storable) =>
      storable ? l.stPresetStore : l.stPresetEmpty;

  /// Two lines of the name at the phone's text size, and never under the 56 dp a finger needs.
  static double height(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    final line =
        MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 12) *
        (style?.height ?? 1.34);
    return (2 * line + 16).clamp(56, double.infinity);
  }

  /// Three to a row, as the glass has them — fewer when a word of a name would not fit a button
  /// and break in the middle at the phone's text size.
  static int columns(BuildContext context, double width, List<String> names) {
    final word = widestWord(
      context,
      names,
      Theme.of(context).textTheme.labelMedium,
    );
    for (final n in const [3, 2]) {
      final button = (width - (n - 1) * _gap) / n;
      if (button - 2 * _gap - _disc - _gap >= word) return n;
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final st = station;
    // one stop for TalkBack: «кнопка 2, Northbound FM», with what a tap and a hold do
    return Semantics(
      container: true,
      button: true,
      selected: on,
      label: name.isEmpty
          ? l.stPresetN('${slot + 1}')
          : '${l.stPresetN('${slot + 1}')}, $name',
      onTapHint: st != null ? l.mobHintListen : null,
      onLongPressHint: onHold != null ? l.mobHintStore : null,
      child: Material(
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
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _gap),
              child: Row(
                children: [
                  if (st != null)
                    StationLogo(name: st.name, logo: logo, size: _disc)
                  else
                    Container(
                      width: _disc,
                      height: _disc,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Text('${slot + 1}', style: text.labelMedium),
                    ),
                  const SizedBox(width: _gap),
                  Expanded(
                    child: Text(
                      name,
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
        ),
      ),
    );
  }
}

/// A station's logo where Radio Browser has one, its disc where it has not or the picture does
/// not come.
class StationLogo extends StatelessWidget {
  const StationLogo({
    super.key,
    required this.name,
    required this.logo,
    required this.size,
    this.label = false,
  });

  final String name;

  /// The logo's address, or ''.
  final String logo;
  final double size;

  /// The disc's whole label rather than its first character, as [StationDisc.label].
  final bool label;

  @override
  Widget build(BuildContext context) {
    final disc = StationDisc(name: name, size: size, label: label);
    if (logo.isEmpty) return disc;
    // logos are drawn for a light ground: a white tile, as station lists show them
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Container(
        width: size,
        height: size,
        color: Colors.white,
        padding: EdgeInsets.all(size * 0.08),
        child: Image.network(
          logo,
          fit: BoxFit.contain,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          errorBuilder: (_, _, _) => disc,
          frameBuilder: (_, child, frame, sync) =>
              frame == null && !sync ? disc : child,
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
