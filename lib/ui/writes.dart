import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device_api.dart';
import '../device/panel/panel_device_api.dart';
import '../device/panel/panel_link.dart';
import '../device/panels.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';

/// Sends a command to the active panel and says in words what went wrong, if anything: a panel
/// that wants its login asks for it; the command is not repeated by itself.
Future<void> act(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function(DeviceApi api) command,
) async {
  final api = ref.read(deviceApiProvider);
  try {
    await command(api);
  } on PanelError catch (e) {
    if (!context.mounted) return;
    final l = AppLocalizations.of(context);
    if (e.unauthorized && api is PanelDeviceApi) {
      await askLogin(context, ref, api);
      return;
    }
    final text = e.locked
        ? l.authLocked
        : e.status == 0
        ? l.appError
        : l.errCode(e.code ?? '${e.status}');
    // it takes the place of what is said and of what waits, so a run of failures says it once
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}

/// The panel's login (the firmware's NETWORK.md, "Authentication"), kept for this panel in the
/// phone's secure storage.
Future<void> askLogin(
  BuildContext context,
  WidgetRef ref,
  PanelDeviceApi api,
) async {
  final id = ref.read(activeIdProvider);
  final login = await showDialog<PanelLogin>(
    context: context,
    builder: (_) => const _LoginDialog(),
  );
  if (login == null || id == null) return;
  api.link.endpoint = api.link.endpoint.withLogin(login.user, login.password);
  await ref.read(loginsProvider.notifier).save(id, login);
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog();

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  final _user = TextEditingController(text: 'admin');
  final _pass = TextEditingController();
  bool _shown = false;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _submit() =>
      Navigator.of(context).pop(PanelLogin(_user.text.trim(), _pass.text));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.authTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _user,
            decoration: InputDecoration(labelText: l.authUser),
            autocorrect: false,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: !_shown,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l.authPass,
              suffixIcon: IconButton(
                tooltip: _shown ? l.passHide : l.passShow,
                icon: Icon(_shown ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _shown = !_shown),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(onPressed: _submit, child: Text(l.authLogin)),
      ],
    );
  }
}
