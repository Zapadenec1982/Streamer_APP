import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/models.dart';
import '../device/panel/panel_link.dart';
import '../device/stations.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'station_card.dart';
import 'writes.dart';

/// The station list and its presets — what the glass's «Улюблені» shows, and what is awkward on
/// the glass: renaming, ordering, deleting, adding a stream by its address (the web's
/// stations/Favorites.svelte). The panel keeps the list; every edit goes back whole with the
/// generation it was made from (lib/device/stations.dart), shown at once, and the page waits for
/// `radio.list_rev` to move before the next — an edit sent before would carry the old generation
/// and be refused.
class FavouritesTab extends ConsumerStatefulWidget {
  const FavouritesTab({super.key});

  @override
  ConsumerState<FavouritesTab> createState() => _FavouritesTabState();
}

class _FavouritesTabState extends ConsumerState<FavouritesTab>
    with AutomaticKeepAliveClientMixin {
  /// The edit on its way, shown until the panel's list moves past [_from].
  StationList? _shown;
  int? _from;
  bool _saving = false;
  Timer? _giveUp;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _giveUp?.cancel();
    super.dispose();
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));

  /// True when the panel took the edit; nothing happens while another is on its way.
  Future<bool> _commit(StationList next, {bool say = true}) async {
    if (_saving) return false;
    final l = AppLocalizations.of(context);
    setState(() {
      _saving = true;
      _shown = next;
      _from = next.rev;
    });
    StationsSave? result;
    try {
      result = await ref.read(deviceApiProvider).saveStations(next);
    } on PanelError catch (e) {
      if (mounted) _say('${l.stSaveFailed}: ${e.code ?? e.status}');
    }
    if (!mounted) return false;
    if (result != StationsSave.saved) {
      if (result == StationsSave.changed) _say(l.stConflict);
      _settle();
      return false;
    }
    if (say) _say(l.stSaved);
    // the panel moves radio.list_rev within a tick; or it did not say so in 3 s
    _giveUp?.cancel();
    _giveUp = Timer(const Duration(seconds: 3), _settle);
    return true;
  }

  /// The panel's list again, and edits again.
  void _settle() {
    _giveUp?.cancel();
    if (!mounted) return;
    ref.invalidate(stationListProvider);
    setState(() {
      _shown = null;
      _from = null;
      _saving = false;
    });
  }

  Future<void> _add(StationList list) async {
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).clearSnackBars();
    final stream = await showDialog<({String url, String name})>(
      context: context,
      builder: (_) => const _AddStream(),
    );
    if (stream == null || stream.url.isEmpty || !mounted) return;
    final why = list.refuse(stream.url);
    if (why != null) {
      final dup = list.stations.where((s) => s.url == stream.url).firstOrNull;
      _say(switch (why) {
        Refusal.url => l.stErrUrl,
        Refusal.urlLong => l.stErrUrlLong,
        Refusal.duplicate => l.stErrDup(dup?.name ?? ''),
        Refusal.full => l.stErrFull,
      });
      return;
    }
    await _commit(list.add(stream.name, stream.url));
  }

  /// The station's sheet. What the last edit said goes first: it would lie over the sheet's foot.
  void _actions(StationList list, int i, bool playing) {
    ScaffoldMessenger.of(context).clearSnackBars();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StationActions(
        list: list,
        index: i,
        playing: playing,
        onPlay: () => act(context, ref, (api) => api.listen(i)),
        onEdit: (next, {say = true}) => _commit(next, say: say),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final read = ref.watch(stationListProvider);
    // the panel's list moved past the edit on its way: that is its answer
    final value = read.value;
    if (_from != null && value != null && value.rev != _from && _saving) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _settle());
    }
    final list = _shown ?? value;
    final now = ref.watch(snapshotProvider.select((s) => s.now));
    final radio = ref.watch(snapshotProvider.select((s) => s.radio));
    final logos = ref.watch(stationLogosProvider).value ?? const {};
    final on = now.kind == NowKind.radio;
    final current = on ? radio.current : -2;

    if (list == null) {
      return Center(
        child: read.hasError
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.stLoadFailed),
                  TextButton(
                    onPressed: () => ref.invalidate(stationListProvider),
                    child: Text(l.appRetry),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Semantics(
            header: true,
            child: Text(
              l.stPresets,
              style: text.titleSmall?.copyWith(color: colors.primary),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: StationPresets(all: false),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l.stAll('${list.stations.length}'),
                    style: text.titleSmall?.copyWith(color: colors.primary),
                  ),
                ),
              ),
              IconButton(
                tooltip: l.stAdd,
                onPressed: _saving ? null : () => _add(list),
                icon: const Icon(Icons.add_link),
              ),
            ],
          ),
        ),
        if (list.stations.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(l.stNone, textAlign: TextAlign.center),
          ),
        for (var i = 0; i < list.stations.length; i++)
          _StationRow(
            station: list.stations[i],
            logo: logos[list.stations[i].uuid] ?? '',
            preset: list.presets.indexOf(i),
            on: i == current,
            busy: _saving,
            onTap: () => act(context, ref, (api) => api.listen(i)),
            onMore: () => _actions(list, i, i == current && now.playing),
          ),
      ],
    );
  }
}

class _StationRow extends StatelessWidget {
  const _StationRow({
    required this.station,
    required this.logo,
    required this.preset,
    required this.on,
    required this.busy,
    required this.onTap,
    required this.onMore,
  });

  final Station station;
  final String logo;

  /// The preset it is on, −1 for none.
  final int preset;
  final bool on;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final host = streamHost(station.url);
    return ListTile(
      leading: StationLogo(name: station.name, logo: logo, size: 40),
      title: Text(station.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        preset >= 0 ? '$host · ${l.stPresetN('${preset + 1}')}' : host,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      selected: on,
      onTap: onTap,
      trailing: IconButton(
        tooltip: l.stActions(station.name),
        onPressed: busy ? null : onMore,
        icon: const Icon(Icons.more_vert),
      ),
    );
  }
}

/// A stream by its address: the address and a name, or nothing.
class _AddStream extends StatefulWidget {
  const _AddStream();

  @override
  State<_AddStream> createState() => _AddStreamState();
}

class _AddStreamState extends State<_AddStream> {
  final _url = TextEditingController();
  final _name = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.stAddTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l.stUrl,
              hintText: 'https://',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            maxLength: StationLimits.name,
            decoration: InputDecoration(labelText: l.stName),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context)
                  .pop((url: _url.text.trim(), name: _name.text)),
          child: Text(l.stAdd),
        ),
      ],
    );
  }
}

/// What can be done to one station: play it, rename it, put it on a preset or take it off, move
/// it, delete it — the web's station dialog.
class _StationActions extends StatefulWidget {
  const _StationActions({
    required this.list,
    required this.index,
    required this.playing,
    required this.onPlay,
    required this.onEdit,
  });

  final StationList list;
  final int index;

  /// It plays now: it is not deleted.
  final bool playing;
  final VoidCallback onPlay;
  final Future<bool> Function(StationList next, {bool say}) onEdit;

  @override
  State<_StationActions> createState() => _StationActionsState();
}

class _StationActionsState extends State<_StationActions> {
  late final _rename = TextEditingController(
    text: widget.list.stations[widget.index].name,
  );

  @override
  void dispose() {
    _rename.dispose();
    super.dispose();
  }

  void _then(StationList next, {bool say = true}) {
    Navigator.of(context).pop();
    widget.onEdit(next, say: say);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final list = widget.list;
    final i = widget.index;
    final st = list.stations[i];
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(st.name, style: text.titleLarge),
            ),
            const SizedBox(height: 4),
            Text(
              st.url,
              style: text.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onPlay();
              },
              icon: const Icon(Icons.play_arrow),
              label: Text(l.stPlay),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _rename,
                    maxLength: StationLimits.name,
                    decoration: InputDecoration(labelText: l.stName),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: TextButton(
                    onPressed: () {
                      final to = _rename.text.trim();
                      if (to.isEmpty || to == st.name) return;
                      _then(list.rename(i, to));
                    },
                    child: Text(l.btnSave),
                  ),
                ),
              ],
            ),
            Text(l.stToPreset, style: text.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var slot = 0; slot < StationList.presetCount; slot++)
                  ChoiceChip(
                    label: Text('${slot + 1}'),
                    selected: list.presets[slot] == i,
                    onSelected: (_) => _then(list.setPreset(i, slot)),
                  ),
                ActionChip(
                  label: Text(l.stUnpreset),
                  onPressed: list.presets.contains(i)
                      ? () => _then(list.setPreset(i, -1))
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: i == 0
                        ? null
                        : () => _then(list.move(i, i - 1), say: false),
                    icon: const Icon(Icons.arrow_upward),
                    label: Text(l.stUp),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: i == list.stations.length - 1
                        ? null
                        : () => _then(list.move(i, i + 1), say: false),
                    icon: const Icon(Icons.arrow_downward),
                    label: Text(l.stDown),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (widget.playing)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l.stDeletePlaying, style: text.bodySmall),
              ),
            Row(
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: widget.playing || list.stations.length <= 1
                      ? null
                      : () => _then(list.remove(i)),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l.stDelete),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l.commonClose),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
