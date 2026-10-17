import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'api.dart';
import 'models.dart';

void main() => runApp(const BuggyTracker());

class BuggyTracker extends StatelessWidget {
    const BuggyTracker({super.key});
    @override
        Widget build(BuildContext context) => MaterialApp(
                title: 'Buggy Tracker', debugShowCheckedModeBanner: false,
                theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xff126957),
                    scaffoldBackgroundColor: const Color(0xfff4f7f5)),
                home: const TrackerPage(),
                );
}

class TrackerPage extends StatefulWidget {
    const TrackerPage({super.key});
    @override
        State<TrackerPage> createState() => _TrackerPageState();
}

class _TrackerPageState extends State<TrackerPage> {
    final _map = MapController();
    final _key = TextEditingController();
    late final TrackerApi _api;
    Timer? _pollTimer, _driveTimer;
    Snapshot? _state;
    DateTime? _receivedAt;
    LatLng? _me;
    String? _selected;
    String? _readError, _driverError;
    String _mode = 'offline';
    bool _stopping = false;
    bool _driver = false, _reading = false, _sending = false, _locating = false;
    int _count = 0, _tick = 0, _generation = 0;

    @override
        void initState() {
            super.initState();
            const configured = String.fromEnvironment('API_BASE_URL');
            _api = TrackerApi(configured.isNotEmpty ? configured :
                    (kIsWeb ? Uri.base.origin : 'http://localhost:8080'));
            _poll();
            _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
        }

    Buggy? get _buggy {
        for (final b in _state?.buggies ?? <Buggy>[]) {
            if (b.id == _selected) return b;
        }
        return null;
    }

    // Server time plus elapsed time avoids relying on synchronized device clocks.
    DateTime get _now => (_state?.serverTime ?? DateTime.now()).add(
            _receivedAt == null ? Duration.zero : DateTime.now().difference(_receivedAt!));

    void _accept(Snapshot state) {
        if (!mounted) return;
        // Poll responses and driver writes may arrive out of order.
        if (_state != null && state.serverTime.isBefore(_state!.serverTime)) return;
        setState(() {
                _state = state;
                _receivedAt = DateTime.now();
                if (!state.buggies.any((b) => b.id == _selected)) {
                _selected = state.buggies.first.id;
                _count = state.buggies.first.occupancy;
                }
                });
    }

    Future<void> _poll() async {
        if (_reading) return;
        _reading = true;
        try {
            final state = await _api.read();
            _accept(state);
            if (mounted) setState(() => _readError = null);
        } catch (_) {
            if (mounted) setState(() => _readError = 'Server unreachable. Showing last known data; retrying…');
        } finally {
            _reading = false;
        }
    }

    Future<LatLng> _position() async {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
            throw Exception('Location permission denied. Allow it in browser/device settings.');
        }
        final p = await Geolocator.getCurrentPosition(locationSettings:
                const LocationSettings(accuracy: LocationAccuracy.high,
                    timeLimit: Duration(seconds: 12)));
        return LatLng(p.latitude, p.longitude);
    }

    Future<void> _locate() async {
        setState(() => _locating = true);
        try {
            final point = await _position().timeout(const Duration(seconds: 20));
            if (!mounted) return;
            setState(() => _me = point);
            _map.move(point, 17);
        } catch (e) {
            if (mounted) _message('Could not locate you: $e. Web GPS needs HTTPS or localhost.');
        } finally {
            if (mounted) setState(() => _locating = false);
        }
    }

    void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(text), duration: const Duration(seconds: 8)));

    void _start(String mode) {
        if (_key.text.trim().isEmpty) {
            _message('Enter the driver passphrase configured on the server.');
            return;
        }
        _generation++;
        _driveTimer?.cancel();
        setState(() { _mode = mode; _driverError = null; _tick = 0; });
        _send();
        _driveTimer = Timer.periodic(const Duration(seconds: 3), (_) => _send());
    }

    Future<void> _send() async {
        if (_sending || _buggy == null || _mode == 'offline') return;
        _sending = true;
        final generation = _generation;
        final id = _selected!;
        final mode = _mode;
        try {
            final point = mode == 'gps' ? await _position().timeout(const Duration(seconds: 20)) :
                simulationPoint(_state!.stops, _tick);
            if (!mounted || generation != _generation) return;
            final state = await _api.write('buggies/$id', _key.text.trim(), {
                    'lat': point.latitude, 'lng': point.longitude,
                    'occupancy': _count, 'source': mode,
                    });
            if (!mounted || generation != _generation) return;
            _tick++;
            _accept(state);
            setState(() { _driverError = null; if (mode == 'gps') _me = point; });
        } catch (e) {
            if (mounted && generation == _generation) {
                setState(() => _driverError = 'Update failed: $e. Retrying; students may see stale data.');
            }
        } finally { _sending = false; }
    }

    Future<void> _stop() async {
        if (_stopping) return;
        _generation++;
        _driveTimer?.cancel();
        setState(() => _stopping = true);
        // Let an already issued update finish before sending the offline event.
        while (_sending && mounted) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        if (!mounted) return;
        try {
            _accept(await _api.write('buggies/${_selected!}', _key.text.trim(), {
                        'occupancy': _count, 'source': 'offline',
                        }));
            if (mounted) setState(() => _driverError = null);
        } catch (e) {
            if (mounted) setState(() => _driverError = 'Stopped locally; server could not be notified: $e');
        } finally {
            if (mounted) setState(() { _mode = 'offline'; _stopping = false; });
        }
    }

    Future<void> _moveDemoRoute() async {
        try {
            final p = _map.camera.center;
            final state = await _api.write('route', _key.text.trim(), {
                    'lat': p.latitude, 'lng': p.longitude,
                    });
            _accept(state);
            if (mounted) _message('Shared demo loop moved to map centre. This is an illustrative route.');
        } catch (e) {
            if (mounted) _message('Could not move route: $e');
        }
    }

    @override
        void dispose() {
            _generation++;
            _pollTimer?.cancel(); _driveTimer?.cancel();
            _api.dispose(); _key.dispose(); _map.dispose();
            super.dispose();
        }

    @override
        Widget build(BuildContext context) {
            final state = _state;
            return Scaffold(
                    appBar: AppBar(title: const Text('Buggy Tracker'), actions: [
                        const Text('Driver'),
                        Switch(value: _driver, onChanged: _mode != 'offline' ? null : (value) {
                            setState(() { _driver = value; _count = _buggy?.occupancy ?? 0; });
                            }),
                    ]),
                    body: state == null ? Center(child: Padding(padding: const EdgeInsets.all(24),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                                const CircularProgressIndicator(), const SizedBox(height: 20),
                                Text(_readError ?? 'Connecting to the campus fleet…'),
                                const SizedBox(height: 12), Text('Server: ${_api.base}'),
                                TextButton(onPressed: _poll, child: const Text('Retry now')),
                            ]))) : Column(children: [
                        if (_readError != null) _banner(_readError!, Colors.orange.shade100),
                        Expanded(child: LayoutBuilder(builder: (context, constraints) {
                                final panel = _panel(state);
                                final map = _mapView(state);
                                if (constraints.maxWidth >= 850) {
                                return Row(children: [SizedBox(width: 350, child: panel), Expanded(child: map)]);
                                }
                                return Column(children: [Expanded(child: map),
                                        SizedBox(height: constraints.maxHeight * .46, child: panel)]);
                                })),
                            ]),
                            );
        }

    Widget _banner(String text, Color color) => Container(width: double.infinity,
            color: color, padding: const EdgeInsets.all(10), child: Text(text));

    Widget _mapView(Snapshot state) => Stack(children: [
            FlutterMap(mapController: _map,
                options: MapOptions(initialCenter: state.stops.first.point, initialZoom: 16),
                children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'org.campus.buggy_tracker'),
                PolylineLayer(polylines: [Polyline(
                        points: [...state.stops.map((s) => s.point), state.stops.first.point],
                        color: const Color(0xff126957), strokeWidth: 5)]),
                MarkerLayer(markers: [
                    for (var i = 0; i < state.stops.length; i++) Marker(
                        point: state.stops[i].point, width: 32, height: 32,
                        child: Tooltip(message: state.stops[i].name, child: CircleAvatar(
                                backgroundColor: Colors.white, child: Text('${i + 1}')))),
                    for (final b in state.buggies.where((b) => b.point != null)) Marker(
                        point: b.point!, width: 52, height: 52,
                        child: Tooltip(message: '${b.name}: ${b.seats} seats • ${b.source}',
                            child: GestureDetector(onTap: _mode != 'offline' ? null : () {
                                setState(() { _selected = b.id; _count = b.occupancy; });
                                }, child: CircleAvatar(
backgroundColor: !b.fresh(_now) || _readError != null ? Colors.grey :
(b.seats == 0 ? Colors.red.shade700 : const Color(0xff126957)),
child: const Icon(Icons.airport_shuttle, color: Colors.white))))),
                    if (_me != null) Marker(point: _me!, width: 25, height: 25,
                        child: const Icon(Icons.my_location, color: Colors.blue, size: 25)),
                ]),
                const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
                ]),
                Positioned(top: 12, right: 12, child: Column(children: [
                            FloatingActionButton.small(heroTag: 'locate', tooltip: 'Find my location',
                                onPressed: _locating ? null : _locate, child: Icon(_locating ? Icons.hourglass_empty : Icons.my_location)),
                            const SizedBox(height: 8),
                            FloatingActionButton.small(heroTag: 'route', tooltip: 'Show route', onPressed: () {
                                _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(
                                                state.stops.map((s) => s.point).toList()), padding: const EdgeInsets.all(50)));
                                }, child: const Icon(Icons.route)),
                ])),
                ]);

    Widget _panel(Snapshot state) {
        final b = _buggy!;
        final fresh = b.fresh(_now) && _readError == null;
        final age = b.positionAt == null ? null : _now.difference(b.positionAt!).inSeconds;
        return ListView(padding: const EdgeInsets.all(20), children: [
                Text(_driver ? 'Driver console' : 'Your campus, connected',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(_driver ? 'Keep this page open while sharing.' : 'Check the route and seats before heading to a stop.'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(initialValue: _selected,
                    key: ValueKey(_selected), decoration: const InputDecoration(labelText: 'Buggy', border: OutlineInputBorder()),
                    items: state.buggies.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
                    onChanged: _mode != 'offline' ? null : (id) => setState(() {
                        _selected = id; _count = _buggy!.occupancy;
                        })),
                const SizedBox(height: 16),
                _banner(!fresh ? 'OFFLINE / STALE — availability unknown' :
                    b.seats == 0 ? 'FULL — wait for another buggy' : '${b.seats} seats available',
                    !fresh ? Colors.grey.shade200 : b.seats == 0 ? Colors.red.shade100 : Colors.green.shade100),
                const SizedBox(height: 8),
                Text('${b.occupancy} / ${b.capacity} passengers • ${b.source.toUpperCase()}'),
                Text(age == null ? 'No location shared yet.' : 'Last location: ${age < 0 ? 0 : age}s ago'),
                if (b.point != null) TextButton.icon(onPressed: () => _map.move(b.point!, 17),
                    icon: const Icon(Icons.center_focus_strong), label: const Text('Show buggy')),
                    if (_driver) ...[
                        const Divider(height: 24),
                              TextField(controller: _key, obscureText: true, enabled: _mode == 'offline',
                                      decoration: const InputDecoration(labelText: 'Driver passphrase', border: OutlineInputBorder())),
                              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                      IconButton(onPressed: _count > 0 ? () => setState(() => _count--) : null,
                                          icon: const Icon(Icons.remove_circle_outline)),
                                      Text('$_count / ${b.capacity} aboard', style: Theme.of(context).textTheme.titleMedium),
                                      IconButton(onPressed: _count < b.capacity ? () => setState(() => _count++) : null,
                                          icon: const Icon(Icons.add_circle_outline)),
                              ]),
                              const Text('Passenger changes publish with the next location update.'),
                              const SizedBox(height: 10),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                      FilledButton.icon(onPressed: _mode == 'offline' ? () => _start('gps') : null,
                                          icon: const Icon(Icons.gps_fixed), label: const Text('Share GPS')),
                                      OutlinedButton.icon(onPressed: _mode == 'offline' ? () => _start('simulation') : null,
                                          icon: const Icon(Icons.play_arrow), label: const Text('Simulate')),
                                      if (_mode != 'offline') OutlinedButton.icon(onPressed: _stopping ? null : _stop,
                                          icon: const Icon(Icons.stop), label: const Text('Stop sharing')),
                              ]),
                              if (_mode != 'offline') Padding(padding: const EdgeInsets.only(top: 8),
                                      child: Text('Sharing mode: $_mode • updates every ~3 seconds')),
                                  if (_driverError != null) Padding(padding: const EdgeInsets.only(top: 8),
                                          child: Text(_driverError!, style: TextStyle(color: Colors.red.shade800))),
                                      TextButton(onPressed: _mode == 'offline' ? _moveDemoRoute : null,
                                              child: const Text('Place demo loop at map centre')),
                                          const Text('Find your location or pan the map first. This moves the shared illustrative loop for everyone; it does not find campus roads.'),
                                          ],
                                          const Divider(height: 28),
                                          Text(state.routeName, style: Theme.of(context).textTheme.titleMedium),
                                          const SizedBox(height: 8),
                                          for (var i = 0; i < state.stops.length; i++) Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                                  child: Text('${i + 1}. ${state.stops[i].name}')),
                                              const Text('↳ Returns to stop 1 • travel follows this order'),
                                                    const SizedBox(height: 12),
                                                    const Text('PoC • No arrival-time prediction or seat reservation. Board only at safe, designated stops.'),
                                                    ]);
    }
}
