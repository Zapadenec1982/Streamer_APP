import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    // a station without a picture shows its disc, as the glass and the web do
    final Widget drawn = now.kind == NowKind.radio && title is TextLabel
        ? Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(size / 16),
            ),
            child: StationDisc(name: title.text, size: size * 0.6, label: true),
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

/// «Звук» and, where the panel has the night leveler, the moon — the web's Player foot.
class _SoundRow extends ConsumerWidget {
  const _SoundRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final leveler = ref.watch(snapshotProvider.select((s) => s.sound.leveler));
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

class _Progress extends StatelessWidget {
  const _Progress({required this.position, required this.duration});

  final Duration position;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme.labelSmall;
    final value = (position.inMilliseconds / duration.inMilliseconds).clamp(
      0.0,
      1.0,
    );
    // TalkBack hears «0:56 of 3:42», not a bar's percent and two loose clocks
    return Semantics(
      container: true,
      label: l.progressPosition,
      value: l.mobOfTime(clock(position), clock(duration)),
      child: ExcludeSemantics(
        child: Column(
          children: [
            LinearProgressIndicator(
              value: value,
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(clock(position), style: text),
                Text(clock(duration), style: text),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          iconSize: 36,
          constraints: const BoxConstraints.tightFor(width: 64, height: 64),
          tooltip: l.transportPrev,
          onPressed: now.canPrevious
              ? () => press(TransportAction.previous)
              : null,
          icon: const Icon(Icons.skip_previous),
        ),
        const SizedBox(width: 24),
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
              onPressed: () => press(TransportAction.toggle),
              icon: Icon(now.playing ? Icons.pause : Icons.play_arrow),
            ),
          ),
        if (now.canToggle) const SizedBox(width: 24),
        IconButton(
          iconSize: 36,
          constraints: const BoxConstraints.tightFor(width: 64, height: 64),
          tooltip: l.transportNext,
          onPressed: now.canNext ? () => press(TransportAction.next) : null,
          icon: const Icon(Icons.skip_next),
        ),
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
