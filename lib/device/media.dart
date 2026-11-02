/// The card's library and the DLNA browser, the parts with no page in them: a port of the
/// firmware's webui/src/lib/media.js. test/media_test.dart holds it to the same cases as
/// tools/tests/test_webui_media.py holds the web's.
library;

/// dlna_client::Command.
abstract final class Browse {
  static const discover = 1;
  static const open = 2;
  static const back = 3;
  static const next = 4;
  static const previous = 5;
  static const queue = 6;
  static const cancel = 7;
}

/// `dlna.browse_cmd`: the command, the row and the revision of the snapshot it was chosen from —
/// dlna_client::encode(). A stale revision makes the browser do nothing rather than the wrong
/// thing, which is why every command carries the one on screen.
int browseCode(int command, int row, int revision) =>
    (revision & 0xffff) * 4096 + (row & 255) * 16 + (command & 15);

final _plainExt = RegExp(r'^[A-Za-z0-9]{2,4}$');

/// A file name without a short, plain extension — strip_ext() of the panel's library.
String trackName(String rel) {
  final name = rel.split('/').last;
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return name;
  return _plainExt.hasMatch(name.substring(dot + 1))
      ? name.substring(0, dot)
      : name;
}

/// The folder of an entry under the root, '' at the top: the dim line of a row.
String trackFolder(String rel) {
  final slash = rel.lastIndexOf('/');
  return slash < 0 ? '' : rel.substring(0, slash);
}

/// What `player.track` wants: the path ready for fopen(), as Playlist::path_at() builds it.
String trackPath(String root, String rel) => '$root/$rel';

/// The filter: every word somewhere in the path (title, album, artist folder), any case.
bool matchesFilter(String rel, String query) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty);
  final hay = rel.toLowerCase();
  return words.every(hay.contains);
}

/// What the last browser command should have done to the path: open a folder of that name, or go
/// back one level.
sealed class BrowseStep {
  const BrowseStep();
}

final class Opened extends BrowseStep {
  const Opened(this.name);

  final String name;
}

final class WentBack extends BrowseStep {
  const WentBack();
}

/// The path above the folder on screen, for the crumbs. The browser publishes only the folder it
/// shows (its title), so the app keeps the names it opened on the way down and checks each new
/// snapshot against them. [crumbs] are the names under «Медіасервери»: the server, then each
/// folder; null stands for levels this page did not see opened (the panel went there) — one tap on
/// it climbs one level. Called once per settled snapshot of a new revision, so a folder named like
/// its parent («CD1» in «CD1») is still one level more.
List<String?> nextCrumbs(
  List<String?> crumbs,
  BrowseStep? step,
  ({String title, bool servers}) view,
) {
  if (view.servers) return const [];
  final top = crumbs.isEmpty ? null : crumbs.last;
  if (step is Opened && view.title == step.name) return [...crumbs, step.name];
  if (step is WentBack &&
      crumbs.length >= 2 &&
      crumbs[crumbs.length - 2] == view.title) {
    return crumbs.sublist(0, crumbs.length - 1);
  }
  if (crumbs.isNotEmpty && top == view.title) return crumbs;
  return [null, view.title];
}
