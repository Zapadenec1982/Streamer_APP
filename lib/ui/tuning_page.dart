import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/keys.dart';
import '../device/speakers.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'link_state.dart';
import 'step_slider.dart';

/// Налаштування › Тонке налаштування, as the web's system/TuningPage.svelte: names and values only.
/// «Звичайна гучність» sits under the loudness, said on the volume's scale, which «Максимум»
/// compresses, and dimmed while the loudness is off. Two follow the port: with one the subsonic
/// sits under it and its slider says so, dimmed; the lift acts only with a port, dimmed at «вимк.»
/// without one.
class TuningPage extends ConsumerWidget {
  const TuningPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final sound = ref.watch(snapshotProvider.select((s) => s.sound));
    final port = sound.portHz;
    final volMax = sound.volMax ?? 100;
    String hzOrOff(int v) => v > 0 ? '$v ${l.unitHz}' : l.eqOff;
    StepSlider slider(
      AudioSetting setting,
      String label,
      int value,
      String Function(int) format, {
      bool enabled = true,
      String? disabledText,
    }) => StepSlider(
      label: label,
      value: value,
      min: setting.min,
      max: setting.max,
      step: setting.step,
      format: format,
      enabled: enabled,
      disabledText: disabledText,
      send: (api, v) => api.setAudio(setting, v),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.pageTuning)),
      body: PanelPage(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            slider(
              AudioSetting.loudness,
              l.eqLoudness,
              sound.loudnessLevel,
              (v) => v > 0 ? '$v %' : l.eqOff,
            ),
            StepSlider(
              label: l.usualTitle,
              value: refShown(sound.loudRef, volMax),
              min: refShown(AudioSetting.loudRef.min, volMax),
              max: 100,
              format: (v) => '$v %',
              enabled: sound.loudnessLevel > 0,
              // the top is the old rule: the loudness counted from the top of the scale
              send: (api, v) => api.setAudio(
                AudioSetting.loudRef,
                v >= 100 ? 100 : refOf(v, volMax),
              ),
            ),
            slider(AudioSetting.width, l.eqWidth, sound.width, (v) => '$v %'),
            slider(
              AudioSetting.monoBass,
              l.eqMonoBass,
              sound.monoBassHz,
              hzOrOff,
            ),
            slider(
              AudioSetting.subsonic,
              l.calHp,
              sound.hpHz,
              hzOrOff,
              enabled: port == 0,
              disabledText: l.spkDSubPort('${subUnder(port)}'),
            ),
            slider(AudioSetting.bassLimiter, l.calXo, sound.bassXoHz, hzOrOff),
            slider(
              AudioSetting.portLift,
              l.calLift,
              sound.portLiftDb,
              (v) => '$v ${l.unitDb}',
              enabled: port > 0,
              disabledText: l.eqOff,
            ),
          ],
        ),
      ),
    );
  }
}
