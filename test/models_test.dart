import 'package:flutter_test/flutter_test.dart';
import 'package:buggy_tracker/models.dart';

void main() {
  test('simulation traverses stops in order and closes the loop', () {
    final stops = [
      Stop({'name': 'A', 'lat': 12.0, 'lng': 77.0}),
      Stop({'name': 'B', 'lat': 12.002, 'lng': 77.0}),
    ];
    expect(simulationPoint(stops, 0).latitude, 12);
    expect(simulationPoint(stops, 15).latitude, closeTo(12.001, .000001));
    expect(simulationPoint(stops, 30).latitude, 12.002);
    expect(simulationPoint(stops, 60).latitude, 12);
  });

  test('freshness expires and offline overrides a recent position', () {
    final json = <String, dynamic>{
      'id': 'b1', 'name': 'Buggy', 'capacity': 6, 'occupancy': 6,
      'source': 'gps', 'lat': 12.0, 'lng': 77.0,
      'positionAt': '2026-01-01T00:00:00Z',
    };
    final buggy = Buggy(json);
    expect(buggy.seats, 0);
    expect(buggy.fresh(DateTime.parse('2026-01-01T00:00:14Z')), isTrue);
    expect(buggy.fresh(DateTime.parse('2026-01-01T00:00:15Z')), isFalse);
    expect(Buggy({...json, 'source': 'offline'}).fresh(
      DateTime.parse('2026-01-01T00:00:01Z')), isFalse);
  });
}
