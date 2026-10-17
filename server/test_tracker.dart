import 'dart:convert';
import 'dart:io';
import 'lib/tracker.dart';

void check(bool condition, String message) {
    if (!condition) throw StateError(message);
}

void rejects(void Function() action) {
    try { action(); } on FormatException { return; }
    throw StateError('Expected validation failure');
}

Future<void> main() async {
    final tracker = Tracker(jsonDecode(await File('config/campus.json').readAsString()) as Map<String, dynamic>);
    final id = tracker.buggies.keys.first;
    final capacity = tracker.buggies[id]!['capacity'] as int;
    final good = <String, dynamic>{'occupancy': capacity, 'source': 'gps', 'lat': 12.0, 'lng': 77.0};
    check(tracker.buggies[id]!['positionAt'] == null, 'No fake location at startup');
    tracker.update(id, good);
    check(tracker.buggies[id]!['occupancy'] == capacity, 'Can report full');
    final before = jsonEncode(tracker.buggies);
    for (final bad in [
            {...good, 'occupancy': -1}, {...good, 'occupancy': capacity + 1},
            {...good, 'occupancy': 1.5}, {...good, 'lat': 91},
            {...good, 'lng': double.nan}, {...good, 'source': 'unknown'},
            {...good, 'lat': null},
    ]) {
        rejects(() => tracker.update(id, bad));
        check(jsonEncode(tracker.buggies) == before, 'Rejected updates must be atomic');
    }
    rejects(() => tracker.update('missing', good));
    final positionAt = tracker.buggies[id]!['positionAt'];
    tracker.update(id, {'occupancy': 0, 'source': 'offline'});
    check(tracker.buggies[id]!['source'] == 'offline', 'Stop marks offline');
    check(tracker.buggies[id]!['positionAt'] == positionAt, 'Stopping does not refresh old location');
    tracker.moveDemoRoute({'lat': 20, 'lng': 70});
    check(tracker.stops.first['lat'] == 20, 'Route moved');
    rejects(() => tracker.moveDemoRoute({'lat': 90, 'lng': 70}));
    stdout.writeln('All tracker checks passed.');
}
