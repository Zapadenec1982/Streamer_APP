import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/speakers.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'labels.dart';
import 'link_state.dart';
import 'meter_poll.dart';
import 'step_field.dart';
import 'tone.dart';
import 'writes.dart';

/// How the port is being found, and the frequency a search by hand is at: kept while the app
/// runs, so a phone that left the page — for a spectrum app, say — comes back to the same step.
class PortSearch extends Notifier<({bool byHand, int hz})> {
  @override
  ({bool byHand, int hz}) build() => (byHand: false, hz: 40);

  void how({required bool byHand}) => state = (byHand: byHand, hz: state.hz);

  void at(int hz) => state = (byHand: state.byHand, hz: hz.clamp(20, 100));
}

final portSearchProvider =
    NotifierProvider<PortSearch, ({bool byHand, int hz})>(PortSearch.new);

/// Колонки › the port's frequency, as the web's service/CalibrationPage.svelte finds it (the
/// firmware's AUDIO.md, "Speaker calibration: port frequency"): step by step, by the streamer's
/// microphone or by hand, each step a line of what to do and the button it needs. Only
/// «Застосувати» and «Записати» write; what was found shows on «Колонки».
class PortPage extends ConsumerStatefulWidget {
  const PortPage({super.key});

  @override
  ConsumerState<PortPage> createState() => _PortPageState();
}

class _PortPageState extends ConsumerState<PortPage> with MeterPoll {
  void _said(String words) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(words)));
  }

  /// The meter offers what it found and writes nothing: this writes it, as measured.
  Future<void> _apply(double hz) async {
    final write = portWrite(hz, measured: true);
    if (await act(context, ref, (api) => api.setSpeakers(write)) && mounted) {
      _said(AppLocalizations.of(context).calPortIs('${write.portHz}'));
    }
  }

  /// The port off and the volume at most 20 % for as long as the tone plays: the streamer keeps
  /// neither, and drops both with the tone, so leaving the page mid-search changes nothing.
  Future<void> _start(int hz) => act(
    context,
    ref,
    (api) => ref
        .read(toneSessionProvider)
        .play(api, hz: hz, portOff: true, volCap: 20),
  );

  /// A step to [hz], heard at once while the tone plays.
  Future<void> _nudge(double hz) async {
    ref.read(portSearchProvider.notifier).at(hz.round());
    if (!ref.read(snapshotProvider).tone.on) return;
    final at = ref.read(portSearchProvider).hz;
    await act(
      context,
      ref,
      (api) => ref.read(toneSessionProvider).play(api, hz: at),
    );
  }

  /// Found by hand: written with where it came from, the speakers ported, the tone stopped and the
  /// source that played before it back.
  Future<void> _write(int hz) async {
    final write = portWrite(hz.toDouble(), measured: false);
    final took = await act(
      context,
      ref,
      (api) =>
          ref.read(toneSessionProvider).stop(api, restore: true, write: write),
    );
    if (took && mounted) {
      _said(AppLocalizations.of(context).calPortIs('${write.portHz}'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    followMeter();
    final search = ref.watch(portSearchProvider);
    final speakers = ref.watch(snapshotProvider.select((s) => s.speakers));
    final measuring = speakers.measuring ?? false;
    final reading = meterReading(speakers);
    final says = reading.status.isEmpty ? '' : l.message(reading.status);
    final found =
        meterOutcome(reading.status, measuring: measuring) ==
            MeterOutcome.found &&
        reading.hz > 0;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(l.calPort)),
      body: PanelPage(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(l.calByMic),
                  selected: !search.byHand,
                  onSelected: (_) =>
                      ref.read(portSearchProvider.notifier).how(byHand: false),
                ),
                ChoiceChip(
                  label: Text(l.calByHand),
                  selected: search.byHand,
                  onSelected: (_) =>
                      ref.read(portSearchProvider.notifier).how(byHand: true),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!search.byHand) ...[
              _Step(
                n: 1,
                title: l.calSPlace,
                text: l.calSPlaceX,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (ch, name) in [
                        (1, l.calSpeakerLeft),
                        (2, l.calSpeakerRight),
                      ])
                        ChoiceChip(
                          label: Text(name),
                          selected: speakers.meterChannel == ch,
                          onSelected: (_) => act(
                            context,
                            ref,
                            (api) => api.setPortMeterChannel(ch),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              _Step(
                n: 2,
                title: l.calSMeasure,
                text: l.calSMeasureX,
                done: reading.hz > 0 && !measuring,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: measuring
                        ? OutlinedButton.icon(
                            onPressed: () => act(
                              context,
                              ref,
                              (api) => api.setPortMeter(false),
                            ),
                            icon: const Icon(Icons.stop),
                            label: Text(l.calMeasureStop),
                          )
                        : FilledButton.icon(
                            onPressed: () => act(
                              context,
                              ref,
                              (api) => api.setPortMeter(true),
                            ),
                            icon: const Icon(Icons.play_arrow),
                            label: Text(l.calMeasure),
                          ),
                  ),
                  // the streamer's own words, its frequency with them
                  if (says.isNotEmpty)
                    Semantics(
                      liveRegion: true,
                      child: Text(says, style: text.bodyLarge),
                    ),
                  if (found)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => _apply(reading.hz),
                        icon: const Icon(Icons.save),
                        label: Text(l.calApply('${reading.hz.round()}')),
                      ),
                    ),
                ],
              ),
            ] else ...[
              _Step(
                n: 1,
                title: l.calSSweep,
                text: l.calSSweepX,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _start(search.hz),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(l.calSet),
                    ),
                  ),
                ],
              ),
              _Step(
                n: 2,
                title: l.calSFind,
                text: l.calSFindX,
                children: [
                  StepField(
                    label: l.calFreq,
                    less: l.calLower,
                    more: l.calHigher,
                    text: '${search.hz} ${l.unitHz}',
                    raw: '${search.hz}',
                    onStep: (dir) => _nudge((search.hz + dir).toDouble()),
                    onSet: _nudge,
                  ),
                ],
              ),
              _Step(
                n: 3,
                title: l.calSPortWrite,
                text: l.calSPortWriteX,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: () => _write(search.hz),
                      icon: const Icon(Icons.save),
                      label: Text(l.calPortWrite('${search.hz.clamp(30, 80)}')),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One step of the search: its number, a short title, a line or two of what to do, and the
/// controls the step needs — nothing a later step needs.
class _Step extends StatelessWidget {
  const _Step({
    required this.n,
    required this.title,
    required this.text,
    this.done = false,
    required this.children,
  });

  final int n;
  final String title;
  final String text;
  final bool done;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme;
    return Card.filled(
      margin: const EdgeInsets.only(top: 8),
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 14, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? colors.primary : colors.secondaryContainer,
                ),
                child: Text(
                  '$n',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: done
                        ? colors.onPrimary
                        : colors.onSecondaryContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(title, style: style.titleMedium),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    text,
                    style: style.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  for (final child in children) ...[
                    const SizedBox(height: 10),
                    child,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
