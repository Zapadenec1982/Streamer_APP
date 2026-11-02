import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../device/speakers.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'link_state.dart';
import 'meter_poll.dart';
import 'speakers_page.dart';
import 'writes.dart';

/// The speakers' wizard, as the web's speakers/Wizard.svelte: step 1 asks what the speakers are —
/// closed ones need nothing more, and «Готово» says so; step 2 finds the port with the streamer's
/// microphone, or by hand on the port page. Nothing is written by a choice, a skip or a
/// measurement: only «Готово» and «Прийняти» write ([wizardWrite]).
class SpeakerWizard extends ConsumerStatefulWidget {
  const SpeakerWizard({super.key});

  @override
  ConsumerState<SpeakerWizard> createState() => _SpeakerWizardState();
}

class _SpeakerWizardState extends ConsumerState<SpeakerWizard> with MeterPoll {
  int _step = 1;
  SpeakerType? _type;
  bool _help = false;

  /// This visit started the measurement: its outcome is the wizard's to show.
  bool _asked = false;

  /// Written, then back to «Колонки». Not written, the wizard stays where it was, to be accepted
  /// again — «Колонки» would show what the streamer never took.
  Future<void> _write(WizardAction action, double found) async {
    final write = wizardWrite(_type ?? SpeakerType.unset, action, found);
    if (write != null &&
        !await act(context, ref, (api) => api.setSpeakers(write))) {
      return;
    }
    if (mounted) context.go('/settings/speakers');
  }

  Future<void> _meter(bool on) async {
    if (on) setState(() => _asked = true);
    await act(context, ref, (api) => api.setPortMeter(on));
  }

  void _leave() => context.go('/settings/speakers');

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    followMeter();
    final speakers = ref.watch(snapshotProvider.select((s) => s.speakers));
    final measuring = speakers.measuring ?? false;
    final reading = meterReading(speakers);
    final outcome = _asked || measuring
        ? meterOutcome(reading.status, measuring: measuring)
        : MeterOutcome.idle;
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget question(String words) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Semantics(
        header: true,
        child: Text(words, style: text.headlineSmall),
      ),
    );
    Widget note(String words) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        words,
        style: text.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
      ),
    );
    final found = reading.hz;
    final hz = found.round();
    final List<Widget> body;
    final List<Widget> actions;
    if (_step == 1) {
      body = [
        question(l.spkQType),
        const SizedBox(height: 8),
        _TypeCard(
          ported: true,
          name: l.spkTPorted,
          words: l.spkTPortedX,
          chosen: _type == SpeakerType.ported,
          onTap: () => setState(() => _type = SpeakerType.ported),
        ),
        const SizedBox(height: 12),
        _TypeCard(
          ported: false,
          name: l.spkTClosed,
          words: l.spkTClosedX,
          chosen: _type == SpeakerType.closed,
          onTap: () => setState(() => _type = SpeakerType.closed),
        ),
        Center(
          child: TextButton(
            onPressed: () => setState(() => _help = !_help),
            child: Text(l.spkHow),
          ),
        ),
        if (_help)
          Card.filled(
            margin: EdgeInsets.zero,
            color: colors.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final line in [l.spkHow1, l.spkHow2, l.spkHow3])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        line,
                        style: text.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ];
      actions = [
        if (_type == SpeakerType.closed)
          FilledButton(
            onPressed: () => _write(WizardAction.done, found),
            child: Text(l.spkDone),
          )
        else
          FilledButton(
            onPressed: _type == null ? null : () => setState(() => _step = 2),
            child: Text(l.spkNext),
          ),
        TextButton(onPressed: _leave, child: Text(l.spkSkip)),
      ];
    } else if (outcome == MeterOutcome.found) {
      final now = speakers.setup.port;
      body = [
        const SizedBox(height: 16),
        Icon(Icons.check_circle, size: 56, color: colors.tertiary),
        Semantics(liveRegion: true, child: question(l.spkResult('$hz'))),
        Card.filled(
          margin: const EdgeInsets.only(top: 4),
          color: colors.surfaceContainerLow,
          child: Column(
            children: [
              // a table, label and value, each wrapping at a large text size
              _Row(
                label: l.spkNow,
                value: now.hz > 0 ? '${now.hz} ${l.unitHz}' : l.calPortNone,
                dim: true,
              ),
              Divider(height: 1, color: colors.surfaceContainerHigh),
              _Row(label: l.spkAfter, value: l.spkAfterV('$hz')),
            ],
          ),
        ),
      ];
      actions = [
        FilledButton(
          onPressed: () => _write(WizardAction.accept, found),
          child: Text(l.spkAccept),
        ),
        OutlinedButton(
          onPressed: () => _write(WizardAction.keep, found),
          child: Text(l.spkKeep),
        ),
      ];
    } else if (outcome == MeterOutcome.failed ||
        outcome == MeterOutcome.doubtful) {
      body = [
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: Icon(Icons.warning, size: 40, color: colors.primary),
        ),
        Semantics(liveRegion: true, child: question(l.spkFailed)),
        if (outcome == MeterOutcome.doubtful && hz > 0)
          note(l.spkDoubtful('$hz')),
        note(l.spkFailedX),
        Card.filled(
          margin: EdgeInsets.zero,
          color: colors.surfaceContainerLow,
          child: Column(
            children: [
              for (final why in [l.spkWhyNoise, l.spkWhyFar, l.spkWhyClosed])
                ListTile(title: Text(why)),
            ],
          ),
        ),
      ];
      actions = [
        FilledButton(onPressed: () => _meter(true), child: Text(l.spkRetry)),
        OutlinedButton(
          onPressed: () => context.go('/settings/speakers/port'),
          child: Text(l.spkByHand),
        ),
        TextButton(
          onPressed: () => _write(WizardAction.keep, found),
          child: Text(l.spkKeep),
        ),
      ];
    } else if (outcome == MeterOutcome.running) {
      final progress = meterProgress(reading.status);
      body = [
        question(l.spkQListen),
        const SizedBox(height: 16),
        Center(
          child: Semantics(
            label: l.spkListening,
            value: '$progress %',
            liveRegion: true,
            child: SizedBox.square(
              dimension: 120,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: progress / 100,
                    strokeWidth: 8,
                    backgroundColor: colors.surfaceContainerHigh,
                  ),
                  Center(
                    child: ExcludeSemantics(
                      child: Text('$progress %', style: text.headlineSmall),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(child: note(l.spkListening)),
      ];
      actions = [
        OutlinedButton.icon(
          onPressed: () => _meter(false),
          icon: const Icon(Icons.stop),
          label: Text(l.spkStop),
        ),
      ];
    } else {
      body = [
        question(l.spkQListen),
        Card.filled(
          margin: const EdgeInsets.only(top: 8),
          color: colors.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.spkByPanel, style: text.titleMedium),
                const SizedBox(height: 6),
                note(l.spkByPanelX),
                _Channels(channel: speakers.meterChannel),
                const SizedBox(height: 8),
                note(l.spkStartX),
              ],
            ),
          ),
        ),
      ];
      actions = [
        FilledButton.icon(
          onPressed: () => _meter(true),
          icon: const Icon(Icons.play_arrow),
          label: Text(l.spkStart),
        ),
        OutlinedButton(
          onPressed: () => context.go('/settings/speakers/port'),
          child: Text(l.spkByHand),
        ),
        // a wrong type is put right here, the choice kept; ← leaves the wizard
        TextButton.icon(
          onPressed: () => setState(() => _step = 1),
          icon: const Icon(Icons.arrow_back),
          label: Text(l.commonBack),
        ),
        TextButton(onPressed: _leave, child: Text(l.spkSkip)),
      ];
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.spkTitle)),
      body: PanelPage(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            ExcludeSemantics(
              child: Row(
                children: [
                  for (var i = 1; i <= 2; i++) ...[
                    if (i > 1) const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: i <= _step
                              ? colors.primary
                              : colors.surfaceContainerHighest,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  l.spkStep('$_step', '2'),
                  style: text.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            ...body,
            const SizedBox(height: 24),
            for (final a in actions)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: a),
          ],
        ),
      ),
    );
  }
}

/// A line of the result's table: what, and its value at the end — dimmed for what was before.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.dim = false});

  final String label;
  final String value;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.bodyLarge;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Expanded(child: Text(label, style: text)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: dim
                    ? text?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )
                    : text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The speaker the meter listens at: left or right.
class _Channels extends ConsumerWidget {
  const _Channels({required this.channel});

  final int channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      children: [
        for (final (ch, name) in [
          (1, l.calSpeakerLeft),
          (2, l.calSpeakerRight),
        ])
          ChoiceChip(
            label: Text(name),
            selected: channel == ch,
            onSelected: (_) =>
                act(context, ref, (api) => api.setPortMeterChannel(ch)),
          ),
      ],
    );
  }
}

/// One of the two kinds of speakers, as a choice: its picture, its name and how to tell it.
class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.ported,
    required this.name,
    required this.words,
    required this.chosen,
    required this.onTap,
  });

  final bool ported;
  final String name;
  final String words;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: chosen,
      child: Material(
        color: chosen ? colors.surfaceContainer : colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: chosen ? colors.primary : colors.surfaceContainerLow,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 120),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 18, 12),
              child: Row(
                children: [
                  SpeakerPicture(
                    ported: ported,
                    portColor: ported ? colors.primary : null,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: text.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          words,
                          style: text.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    chosen
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: chosen ? colors.primary : colors.outline,
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
