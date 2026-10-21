import 'package:latlong2/latlong.dart';

class Stop {
    Stop(Map<String, dynamic> json)
        : name = json['name'] as String,
        point = LatLng((json['lat'] as num).toDouble(), (json['lng'] as num).toDouble());
    final String name;
    final LatLng point;
}

class Buggy {
    Buggy(Map<String, dynamic> json)
        : id = json['id'] as String,
        name = json['name'] as String,
        capacity = json['capacity'] as int,
        occupancy = json['occupancy'] as int,
        source = json['source'] as String,
        point = json['lat'] == null ? null : LatLng(
                (json['lat'] as num).toDouble(), (json['lng'] as num).toDouble()),
        positionAt = DateTime.tryParse(json['positionAt'] as String? ?? '');
    final String id, name, source;
    final int capacity, occupancy;
    final LatLng? point;
    final DateTime? positionAt;
    int get seats => capacity - occupancy;
    bool fresh(DateTime now) => source != 'offline' && positionAt != null &&
        now.difference(positionAt!).inSeconds < 15;
}

class Snapshot {
    Snapshot(Map<String, dynamic> json)
        : routeName = json['routeName'] as String,
        serverTime = DateTime.parse(json['serverTime'] as String),
        stops = (json['stops'] as List).map((s) => Stop(s as Map<String, dynamic>)).toList(),
        buggies = (json['buggies'] as List).map((b) => Buggy(b as Map<String, dynamic>)).toList();
    final String routeName;
    final DateTime serverTime;
    final List<Stop> stops;
    final List<Buggy> buggies;
}

/// A closed loop, interpolated into short steps for a walking demo.
LatLng simulationPoint(List<Stop> stops, int tick) {
    const stepsPerLeg = 30;
    final leg = (tick ~/ stepsPerLeg) % stops.length;
    final fraction = (tick % stepsPerLeg) / stepsPerLeg;
    final from = stops[leg].point;
    final to = stops[(leg + 1) % stops.length].point;
    return LatLng(from.latitude + (to.latitude - from.latitude) * fraction,
            from.longitude + (to.longitude - from.longitude) * fraction);
}
