import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../device/discovery.dart';
import '../device/panel/endpoint.dart';
import '../device/panels.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';

/// The panels the app knows, the demo among them; a tap makes one the app's.
class PanelsPage extends ConsumerWidget {
  const PanelsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final panels = ref.watch(panelsProvider);
    final active = ref.watch(activeIdProvider);
    void choose(String id) {
      ref.read(activeIdProvider.notifier).set(id);
      context.go('/player');
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.mobPanels)),
      body: ListView(
        children: [
          for (final p in panels)
            ListTile(
              leading: const Icon(Icons.speaker),
              title: Text(p.name),
              subtitle: Text(p.address),
              selected: p.id == active,
              trailing: PopupMenuButton<String>(
                onSelected: (_) =>
                    ref.read(panelsProvider.notifier).forget(p.id),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'forget', child: Text(l.mobForget)),
                ],
              ),
              onTap: () => choose(p.id),
            ),
          ListTile(
            leading: const Icon(Icons.speaker_outlined),
            title: Text(l.mobDemoPanel),
            subtitle: Text(l.mobDemoNote),
            selected: active == PanelChoice.demoId,
            onTap: () => choose(PanelChoice.demoId),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.tonalIcon(
              onPressed: () => context.go('/settings/panels/add'),
              icon: const Icon(Icons.add),
              label: Text(l.mobAddPanel),
            ),
          ),
        ],
      ),
    );
  }
}

/// Panels found on the network, and a panel by its address.
class AddPanelPage extends ConsumerStatefulWidget {
  const AddPanelPage({super.key});

  @override
  ConsumerState<AddPanelPage> createState() => _AddPanelPageState();
}

class _AddPanelPageState extends ConsumerState<AddPanelPage> {
  final _discovery = PanelDiscovery();
  final _found = <FoundPanel>[];
  final _address = TextEditingController();
  StreamSubscription<FoundPanel>? _sub;
  bool _searching = true;
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sub = _discovery.found.listen((p) => setState(() => _found.add(p)));
    _discovery.start().catchError(
      (Object _) => setState(() => _searching = false),
    );
    Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _searching = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _discovery.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _add(String id, String name, PanelEndpoint endpoint) async {
    await ref
        .read(panelsProvider.notifier)
        .put(
          SavedPanel(
            id: id,
            name: name,
            host: endpoint.host,
            port: endpoint.port,
          ),
        );
    await ref.read(activeIdProvider.notifier).set(id);
    if (mounted) context.go('/player');
  }

  Future<void> _byAddress() async {
    final l = AppLocalizations.of(context);
    final endpoint = PanelEndpoint.parse(_address.text);
    if (endpoint == null) {
      setState(() => _error = l.mobNotPanel);
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final ok = await isPanel(endpoint);
    if (!mounted) return;
    setState(() => _checking = false);
    if (!ok) {
      setState(() => _error = l.mobNotPanel);
      return;
    }
    await _add(endpoint.address, endpoint.address, endpoint);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(l.mobAddPanel)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _Header(l.mobOnNetwork),
          for (final p in _found)
            ListTile(
              leading: const Icon(Icons.speaker),
              title: Text(p.name),
              subtitle: Text(p.endpoint.address),
              onTap: () => _add(p.id, p.name, p.endpoint),
            ),
          if (_found.isEmpty)
            ListTile(
              leading: _searching
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_find),
              title: Text(_searching ? l.mobSearching : l.mobNoneFound),
              subtitle: _searching ? null : Text(l.mobNoPanelNote),
            ),
          _Header(l.mobByAddress),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _address,
              keyboardType: TextInputType.url,
              autocorrect: false,
              onSubmitted: (_) => _byAddress(),
              decoration: InputDecoration(
                labelText: l.mobAddress,
                hintText: l.mobAddressHint,
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _checking ? null : _byAddress,
                child: _checking
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: text.labelLarge?.color,
                        ),
                      )
                    : Text(l.mobConnect),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}
