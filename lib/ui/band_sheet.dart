import 'package:flutter/material.dart';

import '../device/eq.dart';
import '../l10n/app_localizations.dart';
import 'eq_editor.dart';
import 'labels.dart';
import 'step_field.dart';

/// A band, opened from the equalizer's list, as the web's dsp/BandSheet.svelte has it: «Увімкнена»
/// on top, as the glass's band panel has it — off keeps the numbers ([onTurn]); its type, from the
/// six by the names REW and Equalizer APO use; then its frequency, gain and width with − and +,
/// each value also a field to type into; and «Готово». Each step is heard at once; a step on a
/// band that is off switches it on ([onEdit]). The sheet follows the document as it changes, and
/// goes when its band does — a shorter set from the glass.
Future<void> showBandSheet(
  BuildContext context, {
  required EqEditor editor,
  required int index,
  required void Function(EqBand band) onEdit,
  required void Function(bool on) onTurn,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) =>
      _BandSheet(editor: editor, index: index, onEdit: onEdit, onTurn: onTurn),
);

class _BandSheet extends StatelessWidget {
  const _BandSheet({
    required this.editor,
    required this.index,
    required this.onEdit,
    required this.onTurn,
  });

  final EqEditor editor;
  final int index;
  final void Function(EqBand band) onEdit;
  final void Function(bool on) onTurn;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ValueListenableBuilder(
      valueListenable: editor.doc,
      builder: (context, doc, _) {
        final bands = doc?.bands ?? const <EqBand>[];
        if (index >= bands.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).maybePop();
          });
          return const SizedBox.shrink();
        }
        final band = bands[index];
        void typed(EqParam p, double v) => onEdit(switch (p) {
          EqParam.f => band.copyWith(f: v, on: true),
          EqParam.gain => band.copyWith(gain: v, on: true),
          EqParam.q => band.copyWith(q: v, on: true),
        });
        final named = band.alignment;
        // at a large text size the sheet can be taller than the screen: it scrolls then
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              0,
              24,
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l.eqBandN('${index + 1}'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.eqBandOn),
                  value: band.on,
                  onChanged: onTurn,
                ),
                DropdownMenu<EqType>(
                  key: ValueKey(band.type),
                  expandedInsets: EdgeInsets.zero,
                  label: Text(l.eqType),
                  initialSelection: band.type,
                  dropdownMenuEntries: [
                    for (final type in EqType.values)
                      DropdownMenuEntry(value: type, label: l.eqTypeName(type)),
                  ],
                  onSelected: (type) {
                    if (type != null && type != band.type) {
                      onEdit(band.withType(type).copyWith(on: true));
                    }
                  },
                ),
                const SizedBox(height: 8),
                StepField(
                  less: l.eqLess,
                  more: l.eqMoreStep,
                  label: l.eqFreq,
                  text: l.frequency(band.f),
                  raw: band.f.round().toString(),
                  onStep: (dir) => onEdit(band.step(EqParam.f, dir)),
                  onSet: (v) => typed(EqParam.f, v),
                ),
                StepField(
                  less: l.eqLess,
                  more: l.eqMoreStep,
                  label: l.eqGain,
                  text: l.bandGain(band),
                  raw: l.decimal(band.gain, 1),
                  enabled: band.type.hasGain,
                  signed: true,
                  onStep: (dir) => onEdit(band.step(EqParam.gain, dir)),
                  onSet: (v) => typed(EqParam.gain, v),
                ),
                StepField(
                  less: l.eqLess,
                  more: l.eqMoreStep,
                  // a named alignment is a slope, anything else a width
                  label: named != null ? l.eqSlope : l.eqQWidth,
                  text: named ?? l.decimal(band.q, 2),
                  raw: l.decimal(band.q, 2),
                  onStep: (dir) => onEdit(band.step(EqParam.q, dir)),
                  onSet: (v) => typed(EqParam.q, v),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l.eqDone),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
