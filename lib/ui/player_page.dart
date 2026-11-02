import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/models.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'cover_art.dart';
import 'labels.dart';
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
    // the panel's tint of the cover, as the web's Player wears it
    final backdrop = snapshot.backdrop;
    final station = now.kind == NowKind.radio && now.title is TextLabel;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      color: backdrop == null ? colors.surface : Color(0xFF000000 | backdrop),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final cover = math.min(box.maxWidth - 48, box.maxHeight * 0.42);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: Column(
                children: [
                  if (now.kind.hasOrigin) ...[
                    Text(
                      l.kindName(now.kind).toUpperCase(),
                      style: text.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        letterSpacing: 1.4,
                      ),
                    ),
                    if (now.device.isNotEmpty)
                      Text(now.device, style: text.bodyMedium),
                  ],
                  const SizedBox(height: 16),
                  Semantics(
                    label: l.nowCover,
                    image: true,
                    child: _Cover(now: now, size: cover),
                  ),
                  const SizedBox(height: 20),
                  // a station's face: its name between ‹ and ›, no transport, no progress
                  if (station)
                    StationTitle(name: l.label(now.title), now: now)
                  else
                    Text(
                      l.label(now.title),
                      style: text.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 4),
                  _SubtitleRow(
                    subtitle: now.subtitle == null
                        ? ''
                        : l.label(now.subtitle!),
                    format: l.badge(now.format),
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
            );
          },
        ),
      ),
    );
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
    final key = now.coverKey;
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
    final text = Theme.of(context).textTheme.labelSmall;
    final value = (position.inMilliseconds / duration.inMilliseconds).clamp(
      0.0,
      1.0,
    );
    return Column(
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

/// The volume moves under the finger at once; the panel gets the newest value at most every
/// 150 ms and the last one when the finger lifts (plan, §2 «Підключення»).
class _Volume extends ConsumerStatefulWidget {
  const _Volume();

  @override
  ConsumerState<_Volume> createState() => _VolumeState();
}

class _VolumeState extends ConsumerState<_Volume> {
  static const _every = Duration(milliseconds: 150);

  double? _dragging;
  Timer? _timer;
  int? _pending;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _send(int value) {
    _pending = value;
    if (_timer?.isActive ?? false) return;
    _flush();
    _timer = Timer(_every, _flush);
  }

  void _flush() {
    final value = _pending;
    _pending = null;
    if (value != null && mounted) {
      act(context, ref, (api) => api.setVolume(value));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final snapshot = ref.watch(snapshotProvider);
    final value = _dragging ?? snapshot.volume.toDouble();
    return Row(
      children: [
        IconButton(
          tooltip: snapshot.muted ? l.volumeUnmute : l.volumeMute,
          onPressed: () =>
              act(context, ref, (api) => api.setMuted(!snapshot.muted)),
          icon: Icon(snapshot.muted ? Icons.volume_off : Icons.volume_up),
        ),
        Expanded(
          child: Semantics(
            label: l.volumeLabel,
            child: Slider(
              value: value,
              max: 100,
              onChanged: (v) {
                setState(() => _dragging = v);
                _send(v.round());
              },
              onChangeEnd: (v) {
                _timer?.cancel();
                _pending = v.round();
                _flush();
                setState(() => _dragging = null);
              },
            ),
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '${value.round()}',
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
      ],
    );
  }
}
