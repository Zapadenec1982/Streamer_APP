import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device_api.dart';
import '../device/eq.dart';
import '../device/eq_math.dart';
import '../device/models.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'band_sheet.dart';
import 'eq_editor.dart';
import 'eq_plot.dart';
import 'labels.dart';
import 'link_state.dart';
import 'sound_sheet.dart';
import 'undo.dart';
import 'writes.dart';

/// Налаштування › Звук › Еквалайзер, and the Player's way into it: the equalizer for enthusiasts,
/// as the web's DspPage.svelte has it. The switch; the sounds; the curve with a point per band;
/// the bands as a list, each opened in a sheet; «Скинути «Власний»» for «Власний» alone — a sound
/// never changes: an edit of one makes it «Власний»; the whole system's curve on request.
///
/// The EQ is one document on the panel, edited from here and from the glass ([EqEditor]). An
/// edit is heard at once; the panel writes it a minute after the last one, or at once when this
/// page is left or the app goes to the background. A change made on the glass meanwhile shows
/// here as it is made.
class EqPage extends ConsumerStatefulWidget {
  const EqPage({super.key});

  @override
  ConsumerState<EqPage> createState() => _EqPageState();
}

typedef _Point = ({EqBand band, String preset});

class _EqPageState extends ConsumerState<EqPage> {
  late final DeviceApi _api;
  late final EqEditor _editor = EqEditor(
    _api,
    onConflict: () {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).eqConflict)),
        );
    },
    onError: (e) {
      if (!mounted) return;
      if (_editor.doc.value == null) {
        setState(() => _failed = true);
      } else {
        unawaited(sayFailed(context, ref, e));
      }
    },
  );
  late final AppLifecycleListener _lifecycle;
  bool _failed = false;
  int _selected = 0;
  bool _system = false;

  /// The band a drag took and how it was then, for «Скасувати».
  ({int i, _Point from})? _grabbed;

  @override
  void initState() {
    super.initState();
    _api = ref.read(deviceApiProvider);
    // the app hidden is the page left: the panel writes what it has
    _lifecycle = AppLifecycleListener(onHide: _editor.keep);
    unawaited(_editor.load());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _editor.close();
    super.dispose();
  }

  List<EqBand> get _bands => _editor.doc.value?.bands ?? const [];

  void _setBand(int i, EqBand band) {
    final next = [..._bands];
    if (i >= next.length) return;
    next[i] = band;
    _editor.setBands(next);
  }

  Future<void> _open(int i) async {
    setState(() => _selected = i);
    // a snackbar would lie over the sheet's numbers
    ScaffoldMessenger.of(context).clearSnackBars();
    await showBandSheet(
      context,
      editor: _editor,
      index: i,
      onEdit: (b) => _setBand(i, b),
      onTurn: (on) {
        if (i < _bands.length) _setBand(i, _bands[i].copyWith(on: on));
      },
    );
  }

  void _add() {
    final added = addBand(_bands);
    if (added == null) return;
    _editor.setBands(added.bands);
    unawaited(_open(added.i));
  }

  /// «Скинути «Власний»»: every band off; «Повернути» puts them back.
  void _reset(AppLocalizations l) {
    final was = _bands;
    _editor.setBands(resetBands(was));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(l.eqResetDone),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: l.soundUndo,
            onPressed: () {
              if (mounted) _editor.setBands(was);
            },
          ),
        ),
      );
  }

  void _grab(int i) {
    final d = _editor.doc.value;
    if (d == null || i >= d.bands.length) return;
    _grabbed = (i: i, from: (band: d.bands[i], preset: d.preset));
  }

  /// A point let go somewhere else can be put back from a snackbar: where it was, and the sound
  /// it was then — «Скасувати» chooses a sound the drag made «Власний» again.
  void _release(int i) {
    final g = _grabbed;
    _grabbed = null;
    final d = _editor.doc.value;
    if (g == null || g.i != i || d == null || i >= d.bands.length) return;
    final l = AppLocalizations.of(context);
    String say(EqBand b) => b.type.hasGain
        ? '${l.frequency(b.f)} ${l.bandGain(b)}'
        : l.frequency(b.f);
    ref
        .read(undoProvider)
        .note<_Point>(
          context,
          key: 'eq.band.$i',
          from: g.from,
          to: (band: d.bands[i], preset: d.preset),
          action: l.undoAction,
          text: (a, b) =>
              '${l.eqBandN('${i + 1}')}: ${say(a.band)} → ${say(b.band)}',
          revert: (a) => _revert(i, a),
        );
  }

  void _revert(int i, _Point a) {
    if (mounted) {
      if (a.preset != 'custom') {
        unawaited(_editor.choose(a.preset));
      } else {
        _setBand(i, a.band);
      }
      return;
    }
    // the page is gone: the panel's own document, put back as it was there
    unawaited(
      () async {
        if (a.preset != 'custom') return _api.chooseSound(a.preset);
        final d = await _api.eq();
        if (i >= d.bands.length) return;
        await _api.setEqBands(d.rev, [...d.bands]..[i] = a.band);
      }().catchError((Object _) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sound = ref.watch(snapshotProvider.select((s) => s.sound));
    // the glass edited it: take its version, unless an edit of this page's is on its way
    ref.listen(
      snapshotProvider.select((s) => s.sound.eqRev),
      (_, rev) => _editor.follow(rev),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l.pageEq),
        actions: [
          PopupMenuButton<bool>(
            tooltip: l.eqMenu,
            onSelected: (_) => setState(() => _system = !_system),
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: true,
                checked: _system,
                child: Text(l.eqSystem),
              ),
            ],
          ),
        ],
      ),
      body: PanelPage(
        child: ValueListenableBuilder(
          valueListenable: _editor.doc,
          builder: (context, doc, _) {
            if (doc == null) return _waiting(l);
            return _page(context, l, doc, sound);
          },
        ),
      ),
    );
  }

  Widget _waiting(AppLocalizations l) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: _failed
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.appLoadFailed, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: () {
                    setState(() => _failed = false);
                    unawaited(_editor.load());
                  },
                  icon: const Icon(Icons.refresh),
                  label: Text(l.appRetry),
                ),
              ],
            )
          : const CircularProgressIndicator(),
    ),
  );

  Widget _page(
    BuildContext context,
    AppLocalizations l,
    EqDoc doc,
    SoundState sound,
  ) {
    final colors = Theme.of(context).colorScheme;
    final eqOn = sound.eqOn;
    final bands = doc.bands;
    final selected = _selected < bands.length ? _selected : 0;
    final stages = _system
        ? systemStages(
            bass: sound.bass.toDouble(),
            treble: sound.treble.toDouble(),
            loudDb: sound.loudDb,
            hpHz: sound.hpHz.toDouble(),
            portHz: sound.portHz.toDouble(),
            liftDb: sound.portLiftDb.toDouble(),
          )
        : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(eqOn ? l.eqEnabled : l.eqDisabled),
          value: eqOn,
          onChanged: (on) => act(context, ref, (api) => api.setEqOn(on)),
        ),
        SoundPick(
          presets: doc.presets,
          preset: doc.preset,
          dim: !eqOn,
          onChoose: (id) => unawaited(_editor.choose(id)),
        ),
        const SizedBox(height: 12),
        Opacity(
          opacity: eqOn ? 1 : 0.45,
          child: EqPlot(
            bands: bands,
            fs: doc.fs,
            selected: selected,
            on: eqOn,
            label: l.eqCurve,
            stages: stages,
            onSelect: (i) => setState(() => _selected = i),
            onEdit: _setBand,
            onGrab: _grab,
            onRelease: _release,
          ),
        ),
        if (_system)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(
              l.eqSystemNote,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: 12),
        Opacity(
          opacity: eqOn ? 1 : 0.45,
          child: Card.filled(
            margin: EdgeInsets.zero,
            color: colors.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // every band by its place, on or off, as the glass has them
                for (var i = 0; i < bands.length; i++)
                  _BandRow(index: i, band: bands[i], onTap: () => _open(i)),
                if (bands.isEmpty) ListTile(title: Text(l.eqNoBands)),
                if (bands.length < EqLimits.bands)
                  ListTile(
                    title: Text(
                      l.eqAdd,
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onTap: _add,
                  ),
              ],
            ),
          ),
        ),
        if (doc.preset == 'custom')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: TextButton(
                onPressed: bands.any((b) => b.on) ? () => _reset(l) : null,
                child: Text(l.eqResetMine),
              ),
            ),
          ),
      ],
    );
  }
}

/// A band in the list: its place, its type and frequency, its gain — or «Вимк.», its number
/// hollow and its words fainter, as its point on the plot; still words that read (Android's
/// contrast rule), so not the plot's grey.
class _BandRow extends StatelessWidget {
  const _BandRow({
    required this.index,
    required this.band,
    required this.onTap,
  });

  final int index;
  final EqBand band;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final faint = band.on ? null : colors.onSurfaceVariant;
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: band.on ? colors.secondaryContainer : null,
          border: band.on ? null : Border.all(color: colors.outline, width: 2),
        ),
        child: Text(
          '${index + 1}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: band.on
                ? colors.onSecondaryContainer
                : colors.onSurfaceVariant,
          ),
        ),
      ),
      title: Text(l.eqTypeName(band.type), style: TextStyle(color: faint)),
      subtitle: Text(l.frequency(band.f), style: TextStyle(color: faint)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            band.on ? l.bandGain(band) : l.eqOff,
            style: TextStyle(
              fontSize: 16,
              color: faint,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Icon(Icons.chevron_right, color: colors.outline),
        ],
      ),
    );
  }
}
