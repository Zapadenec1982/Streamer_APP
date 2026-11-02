import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'labels.dart';

/// One number to set: its name over − value +, as the glass's band panel has them. The steps are
/// the quick way; the value is also a field — the exact way — that reads a decimal comma and "1.2k"
/// too ([parseNumber]). The band sheet's numbers and the port's frequency found by hand.
class StepField extends StatefulWidget {
  const StepField({
    super.key,
    required this.label,
    required this.less,
    required this.more,
    required this.text,
    required this.raw,
    required this.onStep,
    required this.onSet,
    this.enabled = true,
    this.signed = false,
  });

  final String label;

  /// What − and + are called: «Менше», «Більше»; «Нижче», «Вище».
  final String less;
  final String more;

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
  State<StepField> createState() => _StepFieldState();
}

class _StepFieldState extends State<StepField> {
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
  void didUpdateWidget(StepField old) {
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
                  tooltip: widget.less,
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
                  tooltip: widget.more,
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
