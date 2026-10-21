class Tracker {
    Tracker(Map<String, dynamic> config) {
        routeName = config['routeName'] as String;
        stops = (config['stops'] as List).map((s) {
                final stop = Map<String, dynamic>.from(s as Map);
                coordinate(stop['lat'], -90, 90);
                coordinate(stop['lng'], -180, 180);
                if (stop['name'] is! String) throw FormatException('Invalid stop name');
                return stop;
                }).toList();
        if (stops.length < 2) throw FormatException('At least two stops required');
        for (final item in config['buggies'] as List) {
            final b = Map<String, dynamic>.from(item as Map);
            if (b['id'] is! String || b['name'] is! String ||
                    b['capacity'] is! int || b['capacity'] < 1 ||
                    buggies.containsKey(b['id'])) {
                throw FormatException('Invalid or duplicate buggy');
            }
            buggies[b['id'] as String] = {
                ...b, 'occupancy': 0, 'lat': null, 'lng': null,
                'source': 'offline', 'updatedAt': null, 'positionAt': null,
            };
        }
        if (buggies.isEmpty) throw FormatException('At least one buggy required');
    }

    late String routeName;
    late List<Map<String, dynamic>> stops;
    final Map<String, Map<String, dynamic>> buggies = {};

    static double coordinate(dynamic value, double min, double max) {
        if (value is! num || !value.isFinite || value < min || value > max) {
            throw FormatException('Invalid coordinate');
        }
        return value.toDouble();
    }

    Map<String, dynamic> snapshot() => {
        'serverTime': DateTime.now().toUtc().toIso8601String(),
            'routeName': routeName, 'stops': stops, 'buggies': buggies.values.toList(),
    };

    void moveDemoRoute(Map<String, dynamic> input) {
        final lat = coordinate(input['lat'], -89, 89);
        final lng = coordinate(input['lng'], -179, 179);
        stops = [
        {'name': 'Demo start', 'lat': lat, 'lng': lng},
        {'name': 'Demo stop 2', 'lat': lat + .0018, 'lng': lng},
        {'name': 'Demo stop 3', 'lat': lat + .0018, 'lng': lng + .0024},
        {'name': 'Demo stop 4', 'lat': lat, 'lng': lng + .0024},
        ];
        routeName = 'Illustrative demo loop near map centre';
    }

    void update(String id, Map<String, dynamic> input) {
        final buggy = buggies[id];
        if (buggy == null) throw FormatException('Unknown buggy');
        final count = input['occupancy'];
        if (count is! int || count < 0 || count > (buggy['capacity'] as int)) {
            throw FormatException('Occupancy must be between zero and capacity');
        }
        final source = input['source'];
        if (!['gps', 'simulation', 'offline'].contains(source)) {
            throw FormatException('Invalid source');
        }
        double? lat;
        double? lng;
        if (source != 'offline') {
            lat = coordinate(input['lat'], -90, 90);
            lng = coordinate(input['lng'], -180, 180);
        }
        final now = DateTime.now().toUtc().toIso8601String();
        buggy.addAll({'occupancy': count, 'source': source, 'updatedAt': now});
        if (lat != null) {
            buggy.addAll({'lat': lat, 'lng': lng, 'positionAt': now});
        }
    }
}
