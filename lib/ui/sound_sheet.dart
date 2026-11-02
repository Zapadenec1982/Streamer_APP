import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device_api.dart';
import '../device/models.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'labels.dart';
import 'web_link.dart';
import 'writes.dart';

/// The daily sound, as the web's «Звук» sheet has it (webui/src/pages/sound/SoundControls.svelte):
/// the sound, Бас and Високі, the loudness, and the way to the equalizer — in the web. No
/// captions, resets or notes beyond what a control needs. The chosen sound is written as the sheet
/// closes.
Future<void> showSoundSheet(BuildContext context, WidgetRef ref) async {
  final api = ref.read(deviceApiProvider);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _SoundSheet(),
  );
  unawaited(api.keepSound().catchError((Object _) {}));
}

/// The sounds the panel offers, read again whenever the EQ document moves (audio.eq_rev).
final soundPresetsProvider = FutureProvider.autoDispose<SoundPresets>((ref) {
  ref.watch(snapshotProvider.select((s) => s.sound.eqRev));
  return ref.watch(deviceApiProvider).soundPresets();
});

class _SoundSheet extends ConsumerWidget {
  const _SoundSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final sound = ref.watch(snapshotProvider.select((s) => s.sound));
    final presets = ref.watch(soundPresetsProvider);
    final text = Theme.of(context).textTheme;
    // at a large text size the sheet can be taller than the screen: it scrolls then
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(l.sysSound, style: text.titleLarge),
            ),
            const SizedBox(height: 12),
            if (!sound.eqOn)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(l.soundEqOff),
                  trailing: FilledButton.tonal(
                    onPressed: () =>
                        act(context, ref, (api) => api.setEqOn(true)),
                    child: Text(l.soundEqOn),
                  ),
                ),
              ),
            switch (presets) {
              AsyncData(:final value) => _SoundPick(
                presets: value,
                dim: !sound.eqOn,
              ),
              AsyncError() => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.appLoadFailed),
                trailing: TextButton(
                  onPressed: () => ref.invalidate(soundPresetsProvider),
                  child: Text(l.appRetry),
                ),
              ),
              _ => const SizedBox(
                height: 56,
                child: Center(child: LinearProgressIndicator()),
              ),
            },
            const SizedBox(height: 8),
            _ToneSlider(
              label: l.soundBass,
              value: sound.bass,
              send: (api, v) => api.setBass(v),
            ),
            _ToneSlider(
              label: l.soundTreble,
              value: sound.treble,
              send: (api, v) => api.setTreble(v),
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.eqLoudness),
              value: sound.loudness,
              onChanged: (on) =>
                  act(context, ref, (api) => api.setLoudness(on)),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.pageEq),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => openWeb(context, ref, 'system/sound/eq'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoundPick extends ConsumerWidget {
  const _SoundPick({required this.presets, required this.dim});

  final SoundPresets presets;
  final bool dim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Opacity(
      opacity: dim ? 0.5 : 1,
      child: DropdownMenu<String>(
        expandedInsets: EdgeInsets.zero,
        label: Text(l.soundStyles),
        initialSelection: presets.presets.contains(presets.preset)
            ? presets.preset
            : null,
        dropdownMenuEntries: [
          for (final id in presets.presets)
            DropdownMenuEntry(value: id, label: l.soundName(id)),
        ],
        onSelected: (id) {
          if (id != null) act(context, ref, (api) => api.chooseSound(id));
        },
      ),
    );
  }
}

/// A tone control: −6…+6 dB, moving under the finger at once, the newest value to the panel at
/// most every 150 ms and the last one as the finger lifts — as the volume.
class _ToneSlider extends ConsumerStatefulWidget {
  const _ToneSlider({
    required this.label,
    required this.value,
    required this.send,
  });

  final String label;
  final int value;
  final Future<void> Function(DeviceApi api, int value) send;

  @override
  ConsumerState<_ToneSlider> createState() => _ToneSliderState();
}

class _ToneSliderState extends ConsumerState<_ToneSlider> {
  double? _dragging;
  Timer? _timer;
  int? _pending;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _flush() {
    final v = _pending;
    _pending = null;
    if (v != null && mounted) act(context, ref, (api) => widget.send(api, v));
  }

  static String _signed(double v) {
    final n = v.round();
    return '${n > 0 ? '+' : ''}$n';
  }

  @override
  Widget build(BuildContext context) {
    final value = _dragging ?? widget.value.toDouble();
    // the name and the value over the slider, so neither wraps at the phone's text size; one node
    // for TalkBack — «Бас, +2» — that it moves a step at a time
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(child: Text(widget.label)),
                ExcludeSemantics(child: Text(_signed(value))),
              ],
            ),
          ),
          Slider(
            value: value,
            min: -6,
            max: 6,
            divisions: 12,
            label: _signed(value),
            semanticFormatterCallback: _signed,
            onChanged: (v) {
              setState(() => _dragging = v);
              _pending = v.round();
              if (!(_timer?.isActive ?? false)) {
                _flush();
                _timer = Timer(const Duration(milliseconds: 150), _flush);
              }
            },
            onChangeEnd: (v) {
              _timer?.cancel();
              _pending = v.round();
              _flush();
              setState(() => _dragging = null);
            },
          ),
        ],
      ),
    );
  }
}
