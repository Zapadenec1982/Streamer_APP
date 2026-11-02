import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../device/eq.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'labels.dart';
import 'step_slider.dart';
import 'writes.dart';

/// The Player's «Звук» sheet: the top of Налаштування › Звук › Тембр і гучність, as the web's
/// sheet is. The chosen sound is written as the sheet closes; the equalizer is the Player's own
/// page, and the sheet goes as it opens.
Future<void> showSoundSheet(BuildContext context, WidgetRef ref) async {
  final api = ref.read(deviceApiProvider);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      // at a large text size the sheet can be taller than the screen: it scrolls then
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                AppLocalizations.of(sheet).sysSound,
                style: Theme.of(sheet).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 12),
            SoundControls(
              onEq: () {
                final router = GoRouter.of(sheet);
                Navigator.of(sheet).pop();
                router.go('/player/eq');
              },
            ),
          ],
        ),
      ),
    ),
  );
  unawaited(api.keepSound().catchError((Object _) {}));
}

/// The EQ document, read again whenever it moves (audio.eq_rev).
final eqDocProvider = FutureProvider.autoDispose<EqDoc>((ref) {
  ref.watch(snapshotProvider.select((s) => s.sound.eqRev));
  return ref.watch(deviceApiProvider).eq();
});

/// The daily sound, as the web's sound/SoundControls.svelte has it — one widget in two places,
/// the Player's sheet and Налаштування › Звук › Тембр і гучність ([page]): the sound, Бас and
/// Високі, the loudness and the way to the equalizer ([onEq]); on the page also the volume's two
/// and the leveler by the clock. No captions, resets or notes beyond what a control needs.
class SoundControls extends ConsumerWidget {
  const SoundControls({super.key, this.page = false, required this.onEq});

  final bool page;
  final VoidCallback onEq;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final sound = ref.watch(snapshotProvider.select((s) => s.sound));
    final doc = ref.watch(eqDocProvider);
    final volMax = sound.volMax;
    final volStart = sound.volStart;
    final schedule = sound.levSchedule;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!sound.eqOn)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l.soundEqOff),
              trailing: FilledButton.tonal(
                onPressed: () => act(context, ref, (api) => api.setEqOn(true)),
                child: Text(l.soundEqOn),
              ),
            ),
          ),
        switch (doc) {
          AsyncData(:final value) => SoundPick(
            presets: value.presets,
            preset: value.preset,
            dim: !sound.eqOn,
            onChoose: (id) => act(context, ref, (api) => api.chooseSound(id)),
          ),
          AsyncError() => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.appLoadFailed),
            trailing: TextButton(
              onPressed: () => ref.invalidate(eqDocProvider),
              child: Text(l.appRetry),
            ),
          ),
          _ => const SizedBox(
            height: 56,
            child: Center(child: LinearProgressIndicator()),
          ),
        },
        const SizedBox(height: 8),
        StepSlider(
          label: l.soundBass,
          value: sound.bass,
          min: -6,
          max: 6,
          format: signedNumber,
          send: (api, v) => api.setBass(v),
        ),
        StepSlider(
          label: l.soundTreble,
          value: sound.treble,
          min: -6,
          max: 6,
          format: signedNumber,
          send: (api, v) => api.setTreble(v),
        ),
        const Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.eqLoudness),
          value: sound.loudness,
          onChanged: (on) => act(context, ref, (api) => api.setLoudness(on)),
        ),
        const Divider(),
        if (page && volMax != null) ...[
          _Caption(l.soundVolume),
          // «Максимум» compresses the scale: 100 % from any client is this
          StepSlider(
            label: l.soundVolMax,
            value: volMax,
            min: 40,
            max: 100,
            step: 5,
            format: (v) => '$v %',
            send: (api, v) => api.setVolMax(v),
          ),
          if (volStart != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.soundVolStart),
              subtitle: Text(
                volStart > 0
                    ? l.soundVolStartN('$volStart')
                    : l.soundVolStartAny,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickStart(context, ref, volStart),
            ),
          const Divider(),
        ],
        if (page && schedule != null) ...[
          // the switch itself is the Player's moon; here it goes by the clock
          _Caption(l.soundLeveler),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.soundLevSched),
            value: schedule,
            onChanged: (on) =>
                act(context, ref, (api) => api.setLevelerSchedule(on: on)),
          ),
          if (schedule) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.soundLevFrom),
              subtitle: Text(_time(context, sound.levFrom)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickTime(context, ref, sound.levFrom, from: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.soundLevTo),
              subtitle: Text(_time(context, sound.levTo)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickTime(context, ref, sound.levTo, from: false),
            ),
          ],
          const Divider(),
        ],
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.pageEq),
          // what plays, said under the name as the Settings page says its values
          subtitle: switch (doc) {
            _ when !sound.eqOn => Text(l.sysEqOff),
            AsyncData(:final value) => Text(l.soundName(value.preset)),
            _ => null,
          },
          trailing: const Icon(Icons.chevron_right),
          onTap: onEq,
        ),
      ],
    );
  }

  static String _time(BuildContext context, int minutes) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );

  /// «Після увімкнення»: as it was, or no louder than 10…50 %.
  static Future<void> _pickStart(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) async {
    final l = AppLocalizations.of(context);
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.soundVolStart),
        children: [
          RadioGroup<int>(
            groupValue: current,
            onChanged: (value) => Navigator.of(context).pop(value),
            child: Column(
              children: [
                for (final n in const [0, 10, 20, 30, 40, 50])
                  RadioListTile<int>(
                    value: n,
                    title: Text(
                      n > 0 ? l.soundVolStartN('$n') : l.soundVolStartAny,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null || picked == current || !context.mounted) return;
    await act(context, ref, (api) => api.setVolStart(picked));
  }

  /// An end of the schedule's window, kept on its step of 5 minutes.
  static Future<void> _pickTime(
    BuildContext context,
    WidgetRef ref,
    int minutes, {
    required bool from,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (picked == null || !context.mounted) return;
    final kept = scheduleMinutes(picked);
    if (kept == minutes) return;
    await act(
      context,
      ref,
      (api) => from
          ? api.setLevelerSchedule(from: kept)
          : api.setLevelerSchedule(to: kept),
    );
  }
}

/// A group's caption, as the web's: sentence case, the panel's style.
class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}

/// The sounds as a dropdown, as the glass has them (sound_sheet.cpp ui_sound_field): those
/// offered while [preset] plays. Dimmed while the EQ is off — still a choice.
class SoundPick extends StatelessWidget {
  const SoundPick({
    super.key,
    required this.presets,
    required this.preset,
    required this.dim,
    required this.onChoose,
  });

  final List<String> presets;
  final String preset;
  final bool dim;
  final ValueChanged<String> onChoose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Opacity(
      opacity: dim ? 0.5 : 1,
      child: DropdownMenu<String>(
        // another sound from elsewhere — a drag making it «Власний», the glass — is shown
        key: ValueKey(preset),
        expandedInsets: EdgeInsets.zero,
        label: Text(l.soundStyles),
        initialSelection: presets.contains(preset) ? preset : null,
        dropdownMenuEntries: [
          for (final id in presets)
            DropdownMenuEntry(value: id, label: l.soundName(id)),
        ],
        onSelected: (id) {
          if (id != null && id != preset) onChoose(id);
        },
      ),
    );
  }
}

/// A time of the leveler's schedule as the panel keeps it: minutes of the day on a step of 5
/// (audio.lev_from, lev_to), the nearest one, 23:55 at the latest.
int scheduleMinutes(TimeOfDay t) =>
    math.min(1435, ((t.hour * 60 + t.minute) / 5).round() * 5);
