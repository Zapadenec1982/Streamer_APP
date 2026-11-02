import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../state/providers.dart';

/// Opens a page of the panel's web interface in the phone's browser: what the app leaves to the
/// web (plan, §1) is a tap away. Without a panel — the demo — it says where that lives.
Future<void> openWeb(BuildContext context, WidgetRef ref, String route) async {
  final uri = ref.read(deviceApiProvider).web(route);
  final opened =
      uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (opened || !context.mounted) return;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).mobInWeb)),
    );
}
