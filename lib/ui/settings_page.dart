import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../device/panels.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'labels.dart';
import 'web_link.dart';

/// The app's own settings. The panel's settings stay in its web interface (plan, §1).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final snapshot = ref.watch(snapshotProvider);
    final language = ref.watch(appLanguageProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.navSettings)),
      body: ListView(
        children: [
          _Header(l.mobPanel),
          switch (ref.watch(activePanelProvider)) {
            NoPanel() => ListTile(
              leading: const Icon(Icons.speaker_outlined),
              title: Text(l.mobNoPanel),
              subtitle: Text(l.mobNoPanelNote),
              onTap: () => context.go('/settings/panels'),
            ),
            DemoPanel() => ListTile(
              leading: const Icon(Icons.speaker_outlined),
              title: Text(l.mobDemoPanel),
              subtitle: Text(l.mobDemoNote),
              onTap: () => context.go('/settings/panels'),
            ),
            RealPanel(:final panel) => ListTile(
              leading: const Icon(Icons.speaker),
              title: Text(panel.name),
              subtitle: Text(panel.address),
              onTap: () => context.go('/settings/panels'),
            ),
          },
          if (ref.watch(activePanelProvider) is RealPanel)
            ListTile(
              leading: const Icon(Icons.settings_applications_outlined),
              title: Text(l.mobPanelSettings),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => openWeb(context, ref, 'system'),
            ),
          _Header(l.mobApp),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(l.pageLanguage),
            subtitle: Text(language.endonym ?? l.mobLangPhone),
            onTap: () => _pickLanguage(context, ref, l, language),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(l.sysScheme),
            subtitle: Text(
              '${l.schemeName(snapshot.scheme)} · ${l.langAsPanel}',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(l.mobLicenses),
            onTap: () => showLicensePage(
              context: context,
              applicationName: l.mobAppName,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickLanguage(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    AppLanguage current,
  ) async {
    final picked = await showDialog<AppLanguage>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.pageLanguage),
        children: [
          RadioGroup<AppLanguage>(
            groupValue: current,
            onChanged: (value) => Navigator.of(context).pop(value),
            child: Column(
              children: [
                for (final language in AppLanguage.values)
                  RadioListTile<AppLanguage>(
                    value: language,
                    title: Text(language.endonym ?? l.mobLangPhone),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) {
      await ref.read(appLanguageProvider.notifier).set(picked);
    }
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
