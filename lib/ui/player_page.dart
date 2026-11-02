import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../device/demo_art.dart';
import '../device/models.dart';
import '../device/panels.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'cover_art.dart';
import 'fit.dart';
import 'labels.dart';
import 'sender.dart';
import 'sound_sheet.dart';
import 'station_card.dart';
import 'writes.dart';

/// What plays, from where, and the hands on it: transport and volume. The web's Player in one
/// column (webui PlayerPage), the glass's rules for the buttons: a 72 dp play disc between bare
/// 64 dp previous and next.
class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final snapshot = ref.watch(snapshotProvider);
    final now = snapshot.now;
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final backdrop = snapshot.backdrop;
    final station = now.kind == NowKind.radio && now.title is TextLabel;
    final subtitle = _SubtitleRow(
      subtitle: now.subtitle == null ? '' : l.label(now.subtitle!),
      format: l.badge(now.format),
    );
    // the cover's colour from the top, fading into the page, as the web's Player wears the panel's
    // tint of it (ui.cover_rgb)
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      decoration: BoxDecoration(
        color: colors.surface,
        gradient: backdrop == null
            ? null
            : RadialGradient(
                center: Alignment.topCenter,
                colors: [Color(0xFF000000 | backdrop), colors.surface],
                transform: const _WebTint(),
              ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          // the cover takes what the screen has left, so the page scrolls only when even a small
          // cover leaves no room
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: CoverColumn(
              height: box.maxHeight - 32,
              smallest: 120,
              top: Column(
                children: [
                  // where it comes from, read as one line; spoken in its own case, not spelt
                  if (now.kind.hasOrigin)
                    MergeSemantics(
                      child: Column(
                        children: [
                          Text(
                            l.kindName(now.kind).toUpperCase(),
                            semanticsLabel: l.kindName(now.kind),
                            style: text.labelMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                              letterSpacing: 1.4,
                            ),
                          ),
                          if (now.device.isNotEmpty)
                            Text(now.device, style: text.bodyMedium),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
              ),
              cover: Semantics(
                label: l.nowCover,
                image: true,
                child: ExcludeSemantics(
                  child: LayoutBuilder(
                    builder: (context, square) =>
                        _Cover(now: now, size: square.maxWidth),
                  ),
                ),
              ),
              bottom: Column(
                children: [
                  const SizedBox(height: 20),
                  // a station's face: its name between ‹ and ›, no transport, no progress
                  if (station) ...[
                    StationTitle(name: l.label(now.title), now: now),
                    const SizedBox(height: 4),
                    subtitle,
                  ] else
                    // what plays, by whom, in what: one stop for TalkBack
                    MergeSemantics(
                      child: Column(
                        children: [
                          Text(
                            l.label(now.title),
                            style: text.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          subtitle,
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (station)
                    const StationPresets()
                  else ...[
                    if (now.duration != null && now.duration! > Duration.zero)
                      _Progress(
                        position: now.position ?? Duration.zero,
                        duration: now.duration!,
                        seekable: now.seekable,
                      ),
                    const SizedBox(height: 8),
                    _Transport(now: now),
                  ],
                  const SizedBox(height: 16),
                  const _Volume(),
                  const SizedBox(height: 8),
                  const _SoundRow(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The web's tint (Shell.svelte, `radial-gradient(130% 560px at 50% 0, tint, transparent)`): an
/// ellipse 130 % of the page's width across and 560 px down, centred on its top edge.
/// RadialGradient draws a circle of the box's shortest side; this stretches it to that ellipse.
class _WebTint extends GradientTransform {
  const _WebTint();

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final side = bounds.shortestSide;
    final top = bounds.topCenter;
    return Matrix4.translationValues(top.dx, top.dy, 0)
      ..multiply(
        Matrix4.diagonal3Values(1.3 * bounds.width / side, 560 / side, 1),
      )
      ..multiply(Matrix4.translationValues(-top.dx, -top.dy, 0));
  }
}

/// The panel's own picture when it has one; the drawn cover while it loads or when there is none.
final coverProvider = FutureProvider.autoDispose.family<Uint8List?, String>(
  (ref, key) => ref.watch(deviceApiProvider).cover(key),
);

class _Cover extends ConsumerWidget {
  const _Cover({required this.now, required this.size});

  final NowPlaying now;
  final double size;

  /// The tuned station's logo from Radio Browser, or ''.
  String _logo(WidgetRef ref) {
    final list = ref.watch(stationListProvider).value;
    final i = ref.watch(snapshotProvider.select((s) => s.radio.current));
    if (list == null || i < 0 || i >= list.stations.length) return '';
    final logos = ref.watch(stationLogosProvider).value ?? const {};
    return logos[list.stations[i].uuid] ?? '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = now.title;
    final key = now.coverKey;
    // the demo's tracks wear the app's own artwork
    if (key != null &&
        now.kind != NowKind.radio &&
        ref.watch(activePanelProvider) is DemoPanel) {
      return DemoCover(art: DemoArt.of(key), size: size);
    }
    // a station without a picture shows its logo, or its disc, as the glass and the web do
    final Widget drawn = now.kind == NowKind.radio && title is TextLabel
        ? Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(size / 16),
            ),
            child: StationLogo(
              name: title.text,
              logo: _logo(ref),
              size: size * 0.6,
              label: true,
            ),
          )
        : CoverArt(coverKey: now.coverKey, source: now.source, size: size);
    if (key == null) return drawn;
    final bytes = ref.watch(coverProvider(key)).value;
    if (bytes == null) return drawn;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 16),
      child: Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => drawn,
      ),
    );
  }
}

/// «Звук», where the panel has the night leveler the moon, and for the card and a media server
/// the way to their list — the web's Player foot, the glass's list button (screen_now.cpp).
class _SoundRow extends ConsumerWidget {
  const _SoundRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final leveler = ref.watch(snapshotProvider.select((s) => s.sound.leveler));
    final list = switch (ref.watch(
      snapshotProvider.select((s) => s.now.kind),
    )) {
      NowKind.card => ('/player/library', l.pageLibrary),
      NowKind.dlna => ('/player/dlna', l.pageDlna),
      _ => null,
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FilledButton.tonalIcon(
          onPressed: () => showSoundSheet(context, ref),
          icon: const Icon(Icons.tune),
          label: Text(l.sysSound),
        ),
        if (leveler != null) ...[
          const SizedBox(width: 12),
          IconButton(
            tooltip: l.soundLeveler,
            isSelected: leveler,
            onPressed: () =>
                act(context, ref, (api) => api.setLeveler(!leveler)),
            icon: const Icon(Icons.bedtime_outlined),
            selectedIcon: const Icon(Icons.bedtime),
          ),
        ],
        if (list case (final route, final label)?) ...[
          const SizedBox(width: 12),
          IconButton.outlined(
            tooltip: label,
            onPressed: () => context.go(route),
            icon: const Icon(Icons.queue_music),
          ),
        ],
      ],
    );
  }
}

class _SubtitleRow extends StatelessWidget {
  const _SubtitleRow({required this.subtitle, required this.format});

  final String subtitle;
  final String format;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        if (format.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              format,
              style: text.labelSmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

/// Where in the track: a bar, or — where the source can seek and someone is there to take it — a
/// slider. A position asked for stays shown until the panel reports one near it.
class _Progress extends ConsumerStatefulWidget {
  const _Progress({
    required this.position,
    required this.duration,
    required this.seekable,
  });

  final Duration position;
  final Duration duration;
  final bool seekable;

  @override
  ConsumerState<_Progress> createState() => _ProgressState();
}

class _ProgressState extends ConsumerState<_Progress> {
  /// Seconds under the finger.
  double? _dragging;

  /// The second asked for, until the panel reports one near it.
  int? _sought;
  Timer? _giveUp;

  @override
  void didUpdateWidget(_Progress old) {
    super.didUpdateWidget(old);
    final sought = _sought;
    if (sought != null && (widget.position.inSeconds - sought).abs() <= 2) {
      _sought = null;
      _giveUp?.cancel();
    }
  }

  @override
  void dispose() {
    _giveUp?.cancel();
    super.dispose();
  }

  void _seek(double seconds) {
    final to = seconds.round();
    setState(() {
      _dragging = null;
      _sought = to;
    });
    _giveUp?.cancel();
    _giveUp = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _sought = null);
    });
    act(context, ref, (api) => api.seek(to));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme.labelSmall;
    final total = widget.duration.inMilliseconds / 1000;
    final at =
        (_dragging ??
                _sought?.toDouble() ??
                widget.position.inMilliseconds / 1000)
            .clamp(0.0, total);
    final here = Duration(milliseconds: (at * 1000).round());
    final clocks = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(clock(here), style: text),
        Text(clock(widget.duration), style: text),
      ],
    );
    if (!widget.seekable) {
      // TalkBack hears «0:56 of 3:42», not a bar's percent and two loose clocks
      return Semantics(
        container: true,
        label: l.progressPosition,
        value: l.mobOfTime(clock(here), clock(widget.duration)),
        child: ExcludeSemantics(
          child: Column(
            children: [
              LinearProgressIndicator(
                value: total > 0 ? at / total : 0,
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
              const SizedBox(height: 6),
              clocks,
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        MergeSemantics(
          child: Semantics(
            label: l.progressPosition,
            child: Slider(
              value: at,
              max: total,
              semanticFormatterCallback: (v) => l.mobOfTime(
                clock(Duration(seconds: v.round())),
                clock(widget.duration),
              ),
              onChanged: (v) => setState(() => _dragging = v),
              onChangeEnd: _seek,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ExcludeSemantics(child: clocks),
        ),
      ],
    );
  }
}

/// Previous, play or pause, next — with the card's shuffle and repeat at the sides, as the web
/// has them. Dimmed while nobody is there to take them (Bluetooth with no phone).
class _Transport extends ConsumerWidget {
  const _Transport({required this.now});

  final NowPlaying now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    void press(TransportAction a) =>
        act(context, ref, (api) => api.transport(a));
    if (!now.canToggle && !now.canPrevious && !now.canNext) {
      return const SizedBox(height: 72);
    }
    final live = now.live;
    final repeat = now.repeat;
    final shuffle = now.shuffle ?? false;
    final buttons = <Widget>[
      if (repeat != null)
        IconButton(
          tooltip: l.transportShuffle,
          isSelected: shuffle,
          onPressed: live
              ? () => act(context, ref, (api) => api.setShuffle(!shuffle))
              : null,
          icon: const Icon(Icons.shuffle),
        ),
      IconButton(
        iconSize: 36,
        constraints: const BoxConstraints.tightFor(width: 64, height: 64),
        tooltip: l.transportPrev,
        onPressed: live && now.canPrevious
            ? () => press(TransportAction.previous)
            : null,
        icon: const Icon(Icons.skip_previous),
      ),
      if (now.canToggle)
        SizedBox.square(
          dimension: 72,
          child: IconButton.filled(
            iconSize: 40,
            tooltip: now.playing ? l.transportPause : l.transportPlay,
            style: IconButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
            ),
            onPressed: live ? () => press(TransportAction.toggle) : null,
            icon: Icon(now.playing ? Icons.pause : Icons.play_arrow),
          ),
        ),
      IconButton(
        iconSize: 36,
        constraints: const BoxConstraints.tightFor(width: 64, height: 64),
        tooltip: l.transportNext,
        onPressed: live && now.canNext
            ? () => press(TransportAction.next)
            : null,
        icon: const Icon(Icons.skip_next),
      ),
      if (repeat != null)
        IconButton(
          tooltip: switch (repeat) {
            1 => l.transportRepeatOne,
            2 => l.transportRepeatAll,
            _ => l.transportRepeatOff,
          },
          isSelected: repeat > 0,
          onPressed: live
              ? () =>
                    act(context, ref, (api) => api.setRepeat((repeat + 1) % 3))
              : null,
          icon: Icon(repeat == 1 ? Icons.repeat_one : Icons.repeat),
        ),
    ];
    // with the queue's two at the sides the row spreads over the width; without them the three
    // stand together, 24 dp apart
    return repeat != null
        ? Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: buttons,
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final (i, b) in buttons.indexed) ...[
                if (i > 0) const SizedBox(width: 24),
                b,
              ],
            ],
          );
  }
}

/// The volume moves under the finger at once and stays where the finger left it until the panel
/// says it is there; the panel gets one value at a time, the newest at most every 150 ms (plan,
/// §2 «Підключення»; [SettingSender]).
class _Volume extends ConsumerStatefulWidget {
  const _Volume();

  @override
  ConsumerState<_Volume> createState() => _VolumeState();
}

class _VolumeState extends ConsumerState<_Volume> {
  late final _sender = SettingSender(
    (value) => mounted
        ? act(context, ref, (api) => api.setVolume(value))
        : Future.value(false),
    onSettled: () {
      if (mounted) setState(() {});
    },
  );

  double? _dragging;

  @override
  void dispose() {
    _sender.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final volume = ref.watch(snapshotProvider.select((s) => s.volume));
    final muted = ref.watch(snapshotProvider.select((s) => s.muted));
    ref.listen(
      snapshotProvider.select((s) => s.volume),
      (_, reported) => _sender.heard(reported),
    );
    final value = _dragging ?? _sender.shows(volume).toDouble();
    final style = Theme.of(context).textTheme.labelLarge;
    return Row(
      children: [
        IconButton(
          tooltip: muted ? l.volumeUnmute : l.volumeMute,
          onPressed: () => act(context, ref, (api) => api.setMuted(!muted)),
          icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
        ),
        Expanded(
          // one node: «Гучність, 32 %», which TalkBack moves up and down
          child: MergeSemantics(
            child: Semantics(
              label: l.volumeLabel,
              child: Slider(
                value: value,
                max: 100,
                onChanged: (v) {
                  setState(() => _dragging = v);
                  _sender.send(v.round());
                },
                onChangeEnd: (v) {
                  _sender
                    ..send(v.round())
                    ..release();
                  setState(() => _dragging = null);
                },
              ),
            ),
          ),
        ),
        // room for «100» at the phone's text size, so the number never wraps; the slider says it
        SizedBox(
          width: textWidth(context, '100', style),
          child: ExcludeSemantics(
            child: Text(
              '${value.round()}',
              textAlign: TextAlign.end,
              style: style,
            ),
          ),
        ),
      ],
    );
  }
}
