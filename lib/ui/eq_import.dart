import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/eq.dart';
import '../device/eq_file.dart';
import '../l10n/app_localizations.dart';
import 'files.dart';
import 'labels.dart';

/// «Імпорт фільтрів», as the web's dsp/ImportDialog.svelte: Equalizer APO or REW text, pasted or
/// from a file, read as it is typed — what will come in and what will not, said before anything
/// is sent. The bands to import, or null.
Future<List<EqBand>?> showEqImport(BuildContext context) =>
    showDialog<List<EqBand>>(
      context: context,
      builder: (_) => const _ImportDialog(),
    );

class _ImportDialog extends ConsumerStatefulWidget {
  const _ImportDialog();

  @override
  ConsumerState<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<_ImportDialog> {
  final _text = TextEditingController();
  String _readError = '';

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final f = await ref.read(phoneFilesProvider).open(FileTypes.text);
      if (f == null || !mounted) return;
      setState(() => _readError = '');
      _text.text = textOf(f.bytes);
    } on PlatformException catch (e) {
      if (mounted) setState(() => _readError = e.message ?? e.code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final p = parseFilters(_text.text);
    final notes = [
      if (p.preamp case final db? when db != 0)
        l.eqImportPreamp(l.decimal(db, _places(db))),
      if (p.unsupported > 0) l.eqImportUnsupported('${p.unsupported}'),
      if (p.unreadable > 0) l.eqImportUnreadable('${p.unreadable}'),
      if (p.extra > 0) l.eqImportExtra('${p.extra}'),
      if (p.clamped > 0) l.eqImportClamped('${p.clamped}'),
    ];
    return AlertDialog(
      title: Text(l.eqImport),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.eqImportHint,
            style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _text,
            minLines: 5,
            maxLines: 7,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.multiline,
            style: text.bodySmall?.copyWith(fontFamily: 'monospace'),
            decoration: InputDecoration(
              labelText: l.eqImport,
              alignLabelWithHint: true,
              hintText: 'Filter 1: ON PK Fc 1000 Hz Gain -3 dB Q 1.41',
              border: const OutlineInputBorder(),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.upload_file),
              label: Text(l.eqImportFile),
            ),
          ),
          // what will come in, said as it changes
          Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_readError.isNotEmpty)
                  Text(_readError, style: TextStyle(color: colors.error))
                else if (_text.text.trim().isNotEmpty) ...[
                  Text(
                    p.bands.isNotEmpty
                        ? l.eqImportN(p.bands.length)
                        : l.eqImportNone,
                    style: p.bands.isEmpty
                        ? TextStyle(color: colors.error)
                        : null,
                  ),
                  for (final line in notes)
                    Text(
                      line,
                      style: text.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: p.bands.isEmpty
              ? null
              : () => Navigator.of(context).pop(p.bands),
          child: Text(l.eqImportGo),
        ),
      ],
    );
  }
}

/// The decimals [x] needs, two at most: the file's -6.4 stays «−6,4», -6 «−6».
int _places(double x) {
  final hundredths = (x * 100).round().abs();
  return hundredths % 100 == 0
      ? 0
      : hundredths % 10 == 0
      ? 1
      : 2;
}
