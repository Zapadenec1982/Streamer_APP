import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../device/demo_art.dart';
import '../device/models.dart';

/// A cover drawn by the app: the scheme's colours at an angle the cover's key picks, and the
/// source's icon. It stands in for a picture until the panel sends one (plan, stage 2).
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    required this.coverKey,
    required this.source,
    required this.size,
  });

  final String? coverKey;
  final SourceId source;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final turn = (coverKey?.hashCode ?? 0) % 360 / 360 * 2 * math.pi;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size / 16),
        gradient: coverKey == null
            ? null
            : LinearGradient(
                colors: [
                  colors.primaryContainer,
                  colors.tertiaryContainer,
                  colors.surfaceContainerHigh,
                ],
                transform: GradientRotation(turn),
              ),
        color: coverKey == null ? colors.surfaceContainerLow : null,
      ),
      child: Icon(
        _icon(source),
        size: size * 0.36,
        color: colors.onPrimaryContainer.withValues(
          alpha: coverKey == null ? 0.25 : 0.4,
        ),
      ),
    );
  }

  static IconData _icon(SourceId source) => switch (source) {
    SourceId.radio => Icons.radio,
    SourceId.airplay => Icons.airplay,
    SourceId.usb => Icons.usb,
    SourceId.bt || SourceId.card => Icons.music_note,
    SourceId.off || SourceId.tone || SourceId.aux => Icons.power_settings_new,
  };
}

/// A demo track's cover: the app's own artwork ([DemoArt]), drawn, never a picture of anyone's.
class DemoCover extends StatelessWidget {
  const DemoCover({super.key, required this.art, required this.size});

  final DemoArt art;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size / 16),
    child: CustomPaint(size: Size.square(size), painter: _ArtPainter(art)),
  );
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.art);

  final DemoArt art;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final random = math.Random(art.seed);
    Color c(int rgb) => Color(0xFF000000 | rgb);
    final p = art.palette;
    final ground = c(p.ground);
    final shade = c(p.shade);
    final accent = c(p.accent);
    final light = c(p.light);
    final far = c(p.far);
    final fill = Paint()..isAntiAlias = true;
    canvas.drawRect(Offset.zero & size, fill..color = ground);
    switch (art.pattern) {
      case 0:
        // a sun going down behind bands that thicken towards the water
        final sky = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [ground, shade],
          ).createShader(Rect.fromLTWH(0, 0, s, s * 0.74));
        canvas.drawRect(Rect.fromLTWH(0, 0, s, s * 0.74), sky);
        final r = s * 0.27;
        final sun = Offset(s * (0.38 + random.nextDouble() * 0.24), s * 0.47);
        canvas.drawCircle(
          sun,
          r,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [light, accent],
            ).createShader(Rect.fromCircle(center: sun, radius: r)),
        );
        var y = sun.dy + r * 0.08;
        for (var i = 1; i <= 5; i++) {
          final band = s * 0.011 * i;
          canvas.drawRect(Rect.fromLTWH(0, y, s, band), sky);
          y += band + s * 0.03;
        }
        canvas.drawRect(
          Rect.fromLTWH(0, s * 0.74, s, s * 0.26),
          fill..color = Color.lerp(ground, shade, 0.5)!,
        );
        for (var i = 0; i < 4; i++) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset(sun.dx, s * (0.79 + i * 0.05)),
                width: r * (1.5 - i * 0.32),
                height: s * 0.012,
              ),
              Radius.circular(s * 0.006),
            ),
            fill..color = accent.withValues(alpha: 0.75 - i * 0.15),
          );
        }
      case 1:
        // rings out of a corner
        final corner = Offset(random.nextBool() ? 0 : s, s);
        final colors = [accent, light, far, shade];
        for (var i = 6; i >= 1; i--) {
          canvas.drawCircle(corner, s * 0.17 * i, fill..color = colors[i % 4]);
        }
      case 2:
        // four tiles, a shape on each
        final half = s / 2;
        final colours = [accent, light, far, shade]..shuffle(random);
        for (var t = 0; t < 4; t++) {
          final tile = Rect.fromLTWH(
            (t % 2) * half,
            (t ~/ 2) * half,
            half,
            half,
          );
          canvas.save();
          canvas.clipRect(tile);
          fill.color = colours[t];
          switch ((t + art.seed) % 4) {
            case 0:
              canvas.drawCircle(tile.center, half * 0.36, fill);
            case 1:
              canvas.drawCircle(tile.bottomLeft, half, fill);
            case 2:
              canvas.drawCircle(tile.bottomCenter, half / 2, fill);
            default:
              canvas.drawRect(tile.deflate(half * 0.18), fill);
          }
          canvas.restore();
        }
      default:
        // hills under a moon, the far ones paler
        canvas.drawCircle(
          Offset(s * 0.72, s * 0.26),
          s * 0.1,
          fill..color = light,
        );
        final layers = [
          Color.lerp(far, light, 0.45)!,
          far,
          Color.lerp(far, shade, 0.55)!,
          shade,
        ];
        for (var layer = 0; layer < layers.length; layer++) {
          final base = s * (0.5 + layer * 0.13);
          final amplitude = s * (0.07 - layer * 0.012);
          final phase = random.nextDouble() * math.pi * 2;
          final path = Path()..moveTo(0, s);
          for (var x = 0.0; x <= s; x += s / 48) {
            path.lineTo(
              x,
              base + amplitude * math.sin(phase + x / s * math.pi * 2.2),
            );
          }
          path
            ..lineTo(s, s)
            ..close();
          canvas.drawPath(path, fill..color = layers[layer]);
        }
    }
  }

  @override
  bool shouldRepaint(_ArtPainter old) => old.art.seed != art.seed;
}
