import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../device/eq.dart';
import '../l10n/app_localizations.dart';
import 'eq_editor.dart';
import 'labels.dart';

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
                _StepRow(
                  label: l.eqFreq,
                  text: l.frequency(band.f),
                  raw: band.f.round().toString(),
                  onStep: (dir) => onEdit(band.step(EqParam.f, dir)),
                  onSet: (v) => typed(EqParam.f, v),
                ),
                _StepRow(
                  label: l.eqGain,
                  text: l.bandGain(band),
                  raw: l.decimal(band.gain, 1),
                  enabled: band.type.hasGain,
                  signed: true,
                  onStep: (dir) => onEdit(band.step(EqParam.gain, dir)),
                  onSet: (v) => typed(EqParam.gain, v),
                ),
                _StepRow(
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

/// One number of a band: its name, its value, − and +. The steps are the quick way; the value is
/// also a field — the exact way — that reads a decimal comma and "1.2k" too ([parseNumber]).
class _StepRow extends StatefulWidget {
  const _StepRow({
    required this.label,
    required this.text,
    required this.raw,
    required this.onStep,
    required this.onSet,
    this.enabled = true,
    this.signed = false,
  });

  final String label;

  /// What the field shows while it is not being typed in.
  final String text;

  /// What typing starts from: the bare number.
  final String raw;
  final ValueChanged<int> onStep;
  final ValueChanged<double> onSet;
  final bool enabled;

  /// Values on both sides of zero: a keyboard with a minus.
  final bool signed;

  @override
  State<_StepRow> createState() => _StepRowState();
}

class _StepRowState extends State<_StepRow> {
  late final _field = TextEditingController(text: widget.text);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _field
          ..text = widget.raw
          ..selection = TextSelection(
            baseOffset: 0,
            extentOffset: widget.raw.length,
          );
      } else {
        _commit();
      }
    });
  }

  @override
  void didUpdateWidget(_StepRow old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.text != _field.text) {
      _field.text = widget.text;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _field.dispose();
    super.dispose();
  }

  void _commit() {
    final v = parseNumber(_field.text);
    if (v != null && v.isFinite) widget.onSet(v);
    _field.text = widget.text;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final button = IconButton.styleFrom(
      backgroundColor: colors.surfaceContainerHighest,
    );
    // the name over − value +, as the glass's band panel has them: neither wraps at a large text
    return Opacity(
      opacity: widget.enabled ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.label),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: l.eqLess,
                  onPressed: widget.enabled ? () => widget.onStep(-1) : null,
                  style: button,
                  icon: const Icon(Icons.remove),
                ),
                Expanded(
                  child: TextField(
                    controller: _field,
                    focusNode: _focus,
                    enabled: widget.enabled,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: true,
                      signed: widget.signed,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp('[0-9.,kK+\\-\u2212 ]'),
                      ),
                    ],
                    // TalkBack names the field by the row's name
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: widget.label,
                    ),
                    onSubmitted: (_) => _focus.unfocus(),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: l.eqMoreStep,
                  onPressed: widget.enabled ? () => widget.onStep(1) : null,
                  style: button,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
