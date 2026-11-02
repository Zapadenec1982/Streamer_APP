// Reads a panel the way the app does and prints what the app would show. It only listens: it
// writes nothing, so it can run against a panel someone is listening to.
//
//   dart run tool/probe_panel.dart modesp-2c4c.local
import 'dart:async';
import 'dart:io';

import 'package:streamer/device/models.dart';
import 'package:streamer/device/panel/endpoint.dart';
import 'package:streamer/device/panel/panel_device_api.dart';
import 'package:streamer/device/panel/panel_link.dart';

Future<void> main(List<String> args) async {
  final endpoint = PanelEndpoint.parse(
    args.isEmpty ? 'modesp-2c4c.local' : args.first,
  );
  if (endpoint == null) {
    stderr.writeln('not an address: ${args.first}');
    exit(2);
  }
  final link = PanelLink(endpoint);
  final ota = await link.getJson('/api/ota');
  stdout.writeln('GET /api/ota: $ota');
  final heard = Completer<void>();
  final sub = link.changes.listen((_) {
    if (link.known && !heard.isCompleted) heard.complete();
  });
  link.start();
  await heard.future.timeout(const Duration(seconds: 10));
  final s = snapshotOf(link.state);
  String text(Label? l) => switch (l) {
    TextLabel(:final text) => '"$text"',
    LineLabel(:final line, :final name, :final count) =>
      '<$line${name == null ? '' : ' name=$name'}${count == null ? '' : ' n=$count'}>',
    null => '-',
  };
  stdout
    ..writeln(
      'keys: ${link.state.length}, panel: ${s.name}, scheme: ${s.scheme}',
    )
    ..writeln(
      'now: ${s.now.kind.name} ${text(s.now.title)} / ${text(s.now.subtitle)}',
    )
    ..writeln(
      '     device "${s.now.device}", format "${s.now.format}", playing ${s.now.playing}',
    )
    ..writeln(
      '     buttons: toggle ${s.now.canToggle}, previous ${s.now.canPrevious}, next ${s.now.canNext}'
      ' (caps ${link.state['audio.transport_caps']})',
    )
    ..writeln(
      '     progress ${s.now.position} / ${s.now.duration}, cover ${s.now.coverKey}',
    )
    ..writeln('volume ${s.volume}${s.muted ? ' muted' : ''}');
  for (final c in s.cards) {
    stdout.writeln(
      'card ${c.card.name}${c.active ? ' (playing)' : ''}: ${text(c.status)}',
    );
  }
  await sub.cancel();
  await link.dispose();
}
