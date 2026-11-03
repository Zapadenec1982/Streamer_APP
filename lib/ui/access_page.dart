import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/maintenance.dart';
import '../device/panel/panel_link.dart';
import '../device/panels.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'caption.dart';
import 'link_state.dart';
import 'writes.dart';

/// Налаштування › Доступ, as the web's system/AccessPage.svelte: who may change the streamer — its
/// login on or off, the name, the password — over `GET`/`POST /api/auth`. A new password needs the
/// current one and 4 characters at least; the name and the switch need only the login itself. What
/// the streamer now expects, the app signs in with ([useLogin]).
class AccessPage extends ConsumerStatefulWidget {
  const AccessPage({super.key});

  @override
  ConsumerState<AccessPage> createState() => _AccessPageState();
}

class _AccessPageState extends ConsumerState<AccessPage> {
  AuthInfo? _auth;
  bool _failed = false;
  bool _busy = false;
  final _name = TextEditingController();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _current, _next, _repeat]) {
      c.addListener(() => setState(() {}));
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _current, _next, _repeat]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final auth = await ref.read(deviceApiProvider).auth();
      if (!mounted) return;
      setState(() => _auth = auth);
      _name.text = auth.username;
    } on PanelError {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _say(String words) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(words)));

  /// A request about the login; a wrong current password in its own words.
  Future<bool> _send(Future<void> Function() request) async {
    setState(() => _busy = true);
    try {
      await request();
      return true;
    } on PanelError catch (e) {
      if (!mounted) return false;
      if (e.code == 'wrong_password') {
        _say(AppLocalizations.of(context).accessWrong);
      } else {
        await sayFailed(context, ref, e);
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setEnabled(bool on) async {
    final l = AppLocalizations.of(context);
    if (!on) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.accessOffQ),
          content: Text(l.accessOffBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.sysCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.accessOff),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    final api = ref.read(deviceApiProvider);
    if (!await _send(() => api.setAuth(enabled: on)) || !mounted) return;
    setState(() => _auth = AuthInfo(enabled: on, username: _auth!.username));
    // nothing to sign in with while the streamer asks for nothing
    if (!on) await useLogin(ref, null);
    if (mounted) _say(on ? l.accessOnDone : l.accessOffDone);
  }

  /// The login the app holds now, if any: a new name or password replaces its part.
  PanelLogin? get _held {
    final id = ref.read(activeIdProvider);
    return id == null ? null : ref.read(loginsProvider)[id];
  }

  Future<void> _saveName() async {
    final l = AppLocalizations.of(context);
    final name = _name.text.trim();
    final api = ref.read(deviceApiProvider);
    if (!await _send(() => api.setAuth(username: name)) || !mounted) return;
    final held = _held;
    if (held != null) await useLogin(ref, PanelLogin(name, held.password));
    if (mounted) _say(l.accessSaved);
  }

  Future<void> _savePassword() async {
    final l = AppLocalizations.of(context);
    final name = _name.text.trim();
    final current = _current.text;
    final next = _next.text;
    final api = ref.read(deviceApiProvider);
    final took = await _send(
      () => api.setAuth(
        username: name,
        currentPassword: current,
        newPassword: next,
      ),
    );
    if (!took || !mounted) return;
    // the app signs in with what the streamer now expects
    await useLogin(ref, PanelLogin(name, next));
    _current.clear();
    _next.clear();
    _repeat.clear();
    if (mounted) _say(l.accessPassDone);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final auth = _auth;
    final id = ref.watch(activeIdProvider);
    final held = id == null ? null : ref.watch(loginsProvider)[id];
    final small = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final nameOk = loginNameOk(_name.text);
    final passOk =
        _current.text.isNotEmpty &&
        loginPasswordOk(_next.text) &&
        _next.text == _repeat.text;
    final Widget body;
    if (auth == null) {
      body = Center(
        child: _failed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.appLoadFailed),
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: Text(l.appRetry),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      );
    } else {
      Widget field(
        TextEditingController c,
        String label, {
        bool secret = false,
        int? maxLength,
        List<String>? hints,
        String? error,
      }) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: TextField(
          controller: c,
          obscureText: secret,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: maxLength,
          autofillHints: hints,
          decoration: InputDecoration(labelText: label, errorText: error),
        ),
      );
      body = ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: Text(l.mobAccessLogin),
            subtitle: Text(auth.enabled ? l.accessLoginOn : l.accessLoginOff),
            value: auth.enabled,
            onChanged: _busy ? null : _setEnabled,
          ),
          if (auth.enabled) ...[
            Caption(l.accessName),
            field(
              _name,
              l.accessName,
              maxLength: 31,
              hints: const [AutofillHints.username],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(l.accessNameRule, style: small),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: FilledButton.tonal(
                  onPressed: _busy || !nameOk ? null : _saveName,
                  child: Text(l.accessSave),
                ),
              ),
            ),
            Caption(l.accessPass),
            field(
              _current,
              l.accessCurrent,
              secret: true,
              hints: const [AutofillHints.password],
            ),
            field(
              _next,
              l.accessNew,
              secret: true,
              maxLength: 63,
              hints: const [AutofillHints.newPassword],
            ),
            // the button waits for the two to match: why, said where it is typed
            field(
              _repeat,
              l.accessRepeat,
              secret: true,
              maxLength: 63,
              hints: const [AutofillHints.newPassword],
              error: _repeat.text.isNotEmpty && _repeat.text != _next.text
                  ? l.accessMismatch
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(l.accessRule, style: small),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: FilledButton(
                  onPressed: _busy || !passOk ? null : _savePassword,
                  child: Text(l.accessChange),
                ),
              ),
            ),
            // the app forgets the login it holds: the next request asks for one
            if (held != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text(l.accessSignOut),
                onTap: () => useLogin(ref, null),
              ),
            ],
          ],
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.pageAccess)),
      body: PanelPage(child: body),
    );
  }
}
