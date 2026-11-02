import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/streamer.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'labels.dart';
import 'link_state.dart';
import 'step_slider.dart';
import 'writes.dart';

/// Налаштування › Екран, as the web's system/DisplayPage.svelte and the glass's screen_display.cpp:
/// the brightness, the standby face's level while music plays, the auto-sleep and the scheme.
class DisplayPage extends ConsumerWidget {
  const DisplayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(snapshotProvider.select((s) => s.streamer));
    final scheme = ref.watch(snapshotProvider.select((s) => s.scheme));
    return Scaffold(
      appBar: AppBar(title: Text(l.sysScreen)),
      body: PanelPage(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            for (final (setting, label, value) in [
              (PanelSetting.backlight, l.sysBrightness, s.backlight),
              (
                PanelSetting.standbyBacklight,
                l.sysStandbyBl,
                s.standbyBacklight,
              ),
            ])
              StepSlider(
                label: label,
                value: value,
                min: setting.min,
                max: setting.max,
                step: setting.step,
                format: (v) => '$v %',
                undo: false,
                send: (api, v) => api.setPanel(setting, v),
              ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bedtime_outlined),
              title: Text(l.sysSleep),
              subtitle: Text(_sleep(l, s.sleepMinutes)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickSleep(context, ref, l, s.sleepMinutes),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.palette_outlined),
              title: Text(l.sysScheme),
              subtitle: Text(l.schemeName(scheme)),
            ),
            // the four schemes as their colours, as the web's swatches
            Wrap(
              spacing: 12,
              children: [
                for (var i = 0; i < schemeSwatches.length; i++)
                  _Swatch(
                    color: Color(schemeSwatches[i]),
                    label: l.schemeName(i),
                    chosen: i == scheme,
                    onTap: () => act(
                      context,
                      ref,
                      (api) => api.setPanel(PanelSetting.scheme, i),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _sleep(AppLocalizations l, int minutes) =>
      minutes > 0 ? l.sysMinutes('$minutes') : l.sysNever;

  static Future<void> _pickSleep(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    int current,
  ) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.sysSleep),
        children: [
          RadioGroup<int>(
            groupValue: current,
            onChanged: (v) => Navigator.of(context).pop(v),
            child: Column(
              children: [
                for (final m in sleepSteps)
                  RadioListTile<int>(value: m, title: Text(_sleep(l, m))),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null || picked == current || !context.mounted) return;
    await act(
      context,
      ref,
      (api) => api.setPanel(PanelSetting.sleepMinutes, picked),
    );
  }
}

/// A scheme as its colour: a circle to tap, ringed when it is the one worn.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
    required this.chosen,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    inMutuallyExclusiveGroup: true,
    checked: chosen,
    label: label,
    button: true,
    child: InkResponse(
      onTap: onTap,
      radius: 28,
      child: SizedBox.square(
        dimension: 48,
        child: Center(
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: chosen
                  ? Border.all(
                      color: Theme.of(context).colorScheme.onSurface,
                      width: 3,
                      strokeAlign: BorderSide.strokeAlignOutside,
                    )
                  : null,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Налаштування › Мова стрімера: what the glass speaks, and every client that has not picked a
/// language of its own (ui.lang). The app's own language is the app's setting.
class PanelLanguagePage extends ConsumerWidget {
  const PanelLanguagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final current = ref.watch(
      snapshotProvider.select((s) => s.streamer.language),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.langPanel)),
      body: PanelPage(
        child: RadioGroup<int>(
          groupValue: current,
          onChanged: (i) {
            if (i != null && i != current) {
              act(
                context,
                ref,
                (api) => api.setPanel(PanelSetting.language, i),
              );
            }
          },
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (var i = 0; i < panelLanguages.length; i++)
                RadioListTile<int>(value: i, title: Text(panelLanguages[i])),
            ],
          ),
        ),
      ),
    );
  }
}
