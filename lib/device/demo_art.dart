/// The demo's own artwork for a track: one of [palettes] and one of [patterns], the same every
/// time. The demo is what a store's reviewer and the store's screenshots show — nobody else's album
/// covers. A key `art:<palette>:<pattern>:…` names both; any other key picks them by its hash.
class DemoArt {
  const DemoArt._({
    required this.palette,
    required this.pattern,
    required this.seed,
  });

  factory DemoArt.of(String key) {
    // FNV-1a over the key: stable from run to run, unlike String.hashCode
    var h = 0x811c9dc5;
    for (final c in key.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    final named = RegExp(r'^art:(\d+):(\d+)').firstMatch(key);
    return DemoArt._(
      palette:
          palettes[(named == null ? h : int.parse(named.group(1)!)) %
              palettes.length],
      pattern:
          (named == null ? h >> 12 : int.parse(named.group(2)!)) % patterns,
      seed: h,
    );
  }

  /// The key a demo track's cover goes by.
  static String key(int palette, int pattern, String title) =>
      'art:$palette:$pattern:$title';

  static const patterns = 4;

  /// Ground, shade, accent, light and far colours, 0xRRGGBB: dusk, sea, sand, copper, mint, pine.
  static const palettes = [
    ArtPalette(0x1F2A44, 0x2E4A6B, 0xF2A65A, 0xF6E3C6, 0xE4572E),
    ArtPalette(0x0B2545, 0x13456B, 0x8DA9C4, 0xEEF4ED, 0x5FA8D3),
    ArtPalette(0x3D2C2E, 0x5A403E, 0xD68C45, 0xF2E3BC, 0x8C5E58),
    ArtPalette(0x2B1A2E, 0x4A2E4D, 0xE07A5F, 0xF4D6CC, 0xC9A227),
    ArtPalette(0x12343B, 0x2D545E, 0xE1B382, 0xF3EDE2, 0x7FB7A4),
    ArtPalette(0x1B2F23, 0x31572C, 0x90A955, 0xECF39E, 0x4F772D),
  ];

  final ArtPalette palette;
  final int pattern;
  final int seed;

  /// The Player's background under the cover, 0xRRGGBB: a dark shade of it, as the panel makes
  /// one from a real cover (`ui.cover_rgb`).
  int get backdrop => palette.ground.darker(0.45);
}

/// A cover's colours, 0xRRGGBB.
class ArtPalette {
  const ArtPalette(this.ground, this.shade, this.accent, this.light, this.far);

  final int ground;
  final int shade;
  final int accent;
  final int light;
  final int far;
}

extension on int {
  /// This colour, 0xRRGGBB, [by] of the way to black.
  int darker(double by) {
    int c(int shift) => (((this >> shift) & 0xFF) * (1 - by)).round();
    return c(16) << 16 | c(8) << 8 | c(0);
  }
}
