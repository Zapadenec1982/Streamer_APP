import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../device/keys.dart';
import '../device/speakers.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'labels.dart';
import 'link_state.dart';
import 'step_slider.dart';

/// Налаштування › Колонки, as the web's system/SpeakersPage.svelte: what has been done about the
/// speakers, said in a line, and the way to do it again; the balance; the equalizer, named as what
/// it is; and the details, each number with where it came from. Nothing here writes without a tap.
class SpeakersPage extends ConsumerWidget {
  const SpeakersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final speakers = ref.watch(snapshotProvider.select((s) => s.speakers));
    final setup = speakers.setup;
    final summary = setup.summary;
    final closed = setup.type == SpeakerType.closed;
    return Scaffold(
      appBar: AppBar(title: Text(l.spkTitle)),
      body: PanelPage(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Card.filled(
              margin: EdgeInsets.zero,
              color: colors.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    children: [
                      ExcludeSemantics(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < 2; i++) ...[
                              if (i > 0) const SizedBox(width: 16),
                              SpeakerPicture(ported: !closed, size: 104),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l.speakerTitle(summary.title),
                        style: text.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      if (summary.line != PortLine.none) ...[
                        const SizedBox(height: 6),
                        Text.rich(
                          TextSpan(
                            children: [
                              if (setup.port.measured && !closed)
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Icon(
                                      Icons.check_circle,
                                      size: 18,
                                      color: colors.tertiary,
                                    ),
                                  ),
                                ),
                              TextSpan(
                                text: l.portLine(summary.line, summary.hz),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                          style: text.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.tonal(
                        onPressed: () => context.go('/settings/speakers/setup'),
                        child: Text(
                          summary.again ? l.spkSetupAgain : l.spkSetup,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _Caption(l.spkPlacement),
            // the balance in half dB here: the key keeps tenths (audio.balance_db10)
            StepSlider(
              label: l.spkBalance,
              value: speakers.balanceDb10,
              min: AudioSetting.balance.min,
              max: AudioSetting.balance.max,
              step: AudioSetting.balance.step,
              format: l.balance,
              ends: (l.spkL, l.spkR),
              send: (api, v) => api.setAudio(AudioSetting.balance, v),
            ),
            const SizedBox(height: 8),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.pageEq),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/settings/sound/eq'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.spkDetails),
              subtitle: switch (_detail(l, setup)) {
                '' => null,
                final value => Text(value),
              },
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/settings/speakers/details'),
            ),
          ],
        ),
      ),
    );
  }

  static String _detail(AppLocalizations l, Speakers setup) {
    if (setup.type == SpeakerType.closed) return l.spkClosed;
    final p = setup.port;
    return p.hz > 0 ? l.portShort(p) : '';
  }
}

/// Колонки › Подробиці: each number with where it came from, and the way to find the port again.
class SpeakerDetailsPage extends ConsumerWidget {
  const SpeakerDetailsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final setup = ref.watch(snapshotProvider.select((s) => s.speakers.setup));
    final sound = ref.watch(snapshotProvider.select((s) => s.sound));
    final p = setup.port;
    final closed = setup.type == SpeakerType.closed;
    Widget row(IconData icon, String title, String value) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.spkDetails)),
      body: PanelPage(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            row(Icons.speaker_outlined, l.spkDType, switch (setup.type) {
              SpeakerType.ported => l.spkTPorted,
              SpeakerType.closed => l.spkTClosed,
              SpeakerType.unset => l.usualUnset,
            }),
            row(
              Icons.graphic_eq,
              l.spkDPort,
              closed
                  ? l.spkDOff
                  : p.hz > 0
                  ? l.portShort(p)
                  : l.calPortNone,
            ),
            row(
              Icons.tune,
              l.calHp,
              p.hz > 0
                  ? l.spkDSubPort('${subUnder(p.hz)}')
                  : sound.hpHz > 0
                  ? '${sound.hpHz} ${l.unitHz}'
                  : l.calOff,
            ),
            row(
              Icons.tune,
              l.calLift,
              p.hz > 0 ? '+${sound.portLiftDb} ${l.unitDb}' : l.spkDOff,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.graphic_eq),
              title: Text(l.spkDFind),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/settings/speakers/port'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The speakers' words for the models.
extension SpeakerWords on AppLocalizations {
  String speakerTitle(SpeakerTitle title) => switch (title) {
    SpeakerTitle.ported => spkPorted,
    SpeakerTitle.closed => spkClosed,
    SpeakerTitle.unset => spkUnset,
  };

  String portLine(PortLine line, int? hz) => switch (line) {
    PortLine.none => '',
    PortLine.measured => spkPortMeasured('$hz'),
    PortLine.manual => spkPortManual('$hz'),
    PortLine.unknown => spkPortNone,
  };

  /// What has been done about the speakers, in a line: the port where there is one to say, what
  /// they are where not (the web's Налаштування row).
  String speakersLine(Speakers setup) {
    final s = setup.summary;
    return s.line == PortLine.none
        ? speakerTitle(s.title)
        : portLine(s.line, s.hz);
  }

  /// «Фазоінвертор 47 Гц · виміряно».
  String portShort(({int hz, bool measured}) port) =>
      spkPortShort('${port.hz}', port.measured ? spkSrcMeasured : spkSrcManual);

  /// The balance in its tenths of a dB: «Центр», «Лівіше · 1,5», «Правіше · 2».
  String balance(int db10) {
    if (db10 == 0) return spkCenter;
    final n = db10.abs() % 10 == 0
        ? '${db10.abs() ~/ 10}'
        : decimal(db10.abs() / 10, 1);
    return db10 < 0 ? spkLeft(n) : spkRight(n);
  }
}

/// A group's caption, as the web's: sentence case, the panel's style.
class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 4),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}

/// A speaker drawn as the web draws it: the cabinet, the tweeter, the woofer with its dust cap,
/// and the port under them — or none, for a closed one.
class SpeakerPicture extends StatelessWidget {
  const SpeakerPicture({
    super.key,
    required this.ported,
    this.size = 90,
    this.portColor,
  });

  final bool ported;

  /// The cabinet's height; it is 0.6 of that wide.
  final double size;

  /// The port's rim, when it is the point of the picture.
  final Color? portColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size(size * 0.6, size),
      painter: _SpeakerPainter(
        ported: ported,
        box: colors.surfaceContainerHigh,
        line: colors.onSurfaceVariant,
        port: portColor ?? colors.onSurfaceVariant,
        hole: colors.surfaceContainerLowest,
      ),
    );
  }
}

class _SpeakerPainter extends CustomPainter {
  _SpeakerPainter({
    required this.ported,
    required this.box,
    required this.line,
    required this.port,
    required this.hole,
  });

  final bool ported;
  final Color box;
  final Color line;
  final Color port;
  final Color hole;

  @override
  void paint(Canvas canvas, Size size) {
    // the web's 60×100 drawing, scaled
    final k = size.height / 100;
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final cabinet = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      Radius.circular(9 * k),
    );
    canvas
      ..drawRRect(cabinet, Paint()..color = box)
      ..drawRRect(cabinet, stroke);
    final cx = size.width / 2;
    final tweeter = ported ? 19.0 : 22.0;
    final woofer = ported ? 50.0 : 60.0;
    canvas
      ..drawCircle(Offset(cx, tweeter * k), 6 * k, stroke)
      ..drawCircle(Offset(cx, woofer * k), (ported ? 17 : 19) * k, stroke)
      ..drawCircle(Offset(cx, woofer * k), 5.5 * k, Paint()..color = line);
    if (ported) {
      final at = Offset(cx, 84 * k);
      canvas
        ..drawCircle(at, 7 * k, Paint()..color = hole)
        ..drawCircle(
          at,
          7 * k,
          Paint()
            ..color = port
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
    }
  }

  @override
  bool shouldRepaint(_SpeakerPainter old) =>
      old.ported != ported ||
      old.box != box ||
      old.line != line ||
      old.port != port ||
      old.hole != hole;
}
