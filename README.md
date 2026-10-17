# Buggy Tracker

A Software Lab proof of concept written in **Dart + Flutter**, with a small **Dart HTTP server**. One person acts as the driver and walks with a phone; another sees that buggy move on a map. You can also demonstrate the flow without GPS using the simulated campus loop.

## What it does

- Student view: map, two selectable buggies, shared route and ordered stops, passenger count, available seats, and a full-buggy message.
- Driver view: select a buggy, enter the demo passphrase, share foreground GPS or simulate movement, and adjust passengers with +/−.
- Server shares state between devices. Drivers publish about every 3 seconds; students poll every 2 seconds. GPS acquisition and network delays can increase this interval.
- Updates older than 15 seconds are marked stale. Unreachable servers and stopped drivers show availability as unknown, rather than promising seats.
- Location access is requested only when you choose **Find my location** or **Share GPS**. Student location stays on that device; driver location is shared.
- No database, paid map key, Firebase project, or accounts needed. Map tiles and initial Flutter web resources need internet access.

The included coordinates are **illustrative coordinates in Bengaluru, not your campus**. The demo loop is made of straight segments, not road directions. Use designated boarding stops, not arbitrary places along a road.

## Requirements

Install Flutter 3.35 or newer (Dart 3.9 or newer), preferably the current stable [Flutter SDK](https://docs.flutter.dev/get-started/install) with its bundled Dart SDK. Ensure `flutter` and `dart` are on PATH. Chrome is useful for development. Run commands below from this project directory.

This repository includes the Flutter web entry point, so `flutter create` is **not required** for the browser demo. The browser build can be used on a laptop, Android phone, or iPhone.

## Quick demo: two browser windows

```bash
flutter pub get
flutter build web
export DRIVER_KEY='campus-demo-2026'
dart server/bin/server.dart
```

Open **http://localhost:8080** in two separate windows:

1. Leave the first window in student mode.
2. In the second, turn on **Driver**, select **Buggy 01**, and enter `campus-demo-2026`.
3. Click **Simulate**, then **Show buggy**. The marker moves around the route in stop order.
4. Increase passengers to 6. Within a few seconds, the student view shows **FULL — wait for another buggy**.
5. Decrease the count to show seats becoming available.
6. Click **Stop sharing**. The student view marks that buggy offline.
7. Optionally use a third window to simulate **Buggy 02**. Use only one driver window per buggy.

The server runs in the terminal until Ctrl+C. Restarting clears all live state and reloads `config/campus.json`.

## Two devices on the same Wi-Fi

1. Build and start the server on your laptop as above. It listens on all network interfaces on port 8080.
2. Find the laptop's Wi-Fi IPv4 address using your system's network settings (for example `192.168.1.20`).
3. Open `http://192.168.1.20:8080` on both devices. Replace that example IP with the actual laptop IP. **Do not use localhost on the other device**: that points to the device itself.
4. Use driver simulation on one device and student mode on the other. The app automatically uses the server that served its page.

Allow inbound TCP port 8080 if your firewall prompts. Campus Wi-Fi may isolate clients; a shared hotspot is an alternative. Both devices still need internet for the map tiles.

**Plain HTTP over a LAN works for simulation, but usually cannot access browser GPS.** Use the next section for the walking demo.

## Real GPS walking demo

Browser geolocation requires a secure context: **HTTPS**, or `localhost` on the device running the browser. An ordinary `http://192.168…` address does not qualify. See the [geolocator web documentation](https://pub.dev/packages/geolocator#web).

Choose one of these setups:

- **Android phone with USB debugging:** connect it to the laptop, install Android platform tools, and run `adb reverse tcp:8080 tcp:8080`. Open `http://localhost:8080` in Chrome **on the connected Android phone**. That localhost URL forwards to the laptop server and permits browser geolocation. The student can use the laptop browser or LAN URL. This does not apply to iPhones.
- **HTTPS hosting/reverse proxy:** expose this entire server through an HTTPS address with a certificate trusted by the phones. Open the same HTTPS URL on both phones. Proxy both `/api/*` and the web files to port 8080. No separate API URL is needed. A tunnel can also serve this purpose, but anyone with the URL can read live locations; use only demo data and shut it down afterward.

                                                                                                                                                                                          Then:

                                                                                                                                                                                          1. In the driver window, select the buggy and enter the server passphrase.
                                                                                                                                                                                          2. Tap the map's **Find my location** button and allow location access. The blue marker represents this device.
                                                                                                                                                                                          3. Before sharing, click **Place demo loop at map centre** to put an illustrative route beside your location. This updates the route for all viewers. Alternatively configure the actual campus route below.
                                                                                                                                                                                          4. Press **Share GPS** and walk outside with the phone. Keep the page visible and the screen awake. The student sees the buggy's new coordinates after publication and polling.
                                                                                                                                                                                          5. Adjust passengers as people board/leave. Changes publish with the next successful location update.
                                                                                                                                                                                          6. Press **Stop sharing** at the end. Closing the page or losing signal causes its last update to become stale after 15 seconds.

                                                                                                                                                                                          GPS may be inaccurate indoors or when the device grants only approximate location. If access is denied, allow it in browser/device settings and retry. If GPS fails, the app reports an error; it does not silently substitute simulated locations.

## Configure the actual campus

Edit `config/campus.json` before starting the server:

- `routeName`: your route's display name.
- `stops`: ordered objects with `name`, `lat`, and `lng` in decimal degrees. Use at least two points. The last connects back to the first.
- `buggies`: unique IDs, display names, and positive integer capacities.

The PoC gives all buggies the same loop. Coordinates between stops are straight lines. Add points along roads if needed for the presentation; this version treats each point as a labelled stop. It does not match GPS to roads or infer a driver's future turn. **Share GPS** publishes the real position even if it is off the configured route.

The **Place demo loop at map centre** button replaces the route in memory with a small rectangle. It does not modify the config file and resets on server restart. Stop all simulations before relocating the loop so their markers do not jump unexpectedly.

## Development and checks

For hot reload, run the Dart server in one terminal, then use another:

```bash
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080
```

The development URL uses a different port; the API supports CORS for this workflow. `API_BASE_URL` must include the scheme and no `/api` suffix. For a release build served by this server, omit the define so the API uses the page's origin.

```bash
dart format lib server test
flutter analyze
flutter test
dart server/test_tracker.dart
```

With a disposable server running, test HTTP authentication, validation, and cross-client state:

```bash
DRIVER_KEY='campus-demo-2026' python3 scripts/smoke_test.py http://localhost:8080
```

The smoke test temporarily changes the first buggy and finishes by marking it offline. Do not run it during a live presentation.

                                                                                                                                                                                         **Validation status:** Flutter and Dart were not available in the authoring environment. The app has not yet been compiled or run there; the Dart/Flutter tests above are provided for verification on your development machine. A successful browser build still needs the two-device/GPS acceptance demo described above.

## Project structure and data flow

```text
lib/main.dart              Responsive student/driver UI and location publishing
lib/models.dart            Shared-state decoding, freshness, simulation geometry
lib/api.dart               HTTP requests and errors
server/bin/server.dart     Static web server and authenticated write API
server/lib/tracker.dart    In-memory state and validation
config/campus.json         Route and buggy definitions
web/index.html             Flutter web bootstrap entry
server/test_tracker.dart   Dependency-free domain checks
scripts/smoke_test.py      HTTP integration checks against a running server
test/models_test.dart      Simulation and freshness checks
```

```text
Driver GPS / simulator + passenger controls
│ PUT /api/buggies/:id (driver passphrase)
▼
Dart server's in-memory state
│ GET /api/state every 2 seconds
▼
Student map + seats + freshness indicator
```

`GET /api/state` returns the route, stops, buggies, and server time. Buggies have `source` (`gps`, `simulation`, or `offline`), `occupancy`, coordinates, and a server-assigned `positionAt` timestamp. New buggies have no coordinates until a driver publishes. `PUT /api/route` accepts a demo loop anchor `{ "lat": ..., "lng": ... }`.

Both PUT endpoints require `X-Driver-Key`. The server validates coordinates and occupancy before changing state. `DRIVER_KEY` must contain at least 8 characters; there is no built-in password. Optional environment variables: `PORT` (8080), `HOST` (0.0.0.0), `WEB_ROOT` (build/web), and `CAMPUS_CONFIG` (config/campus.json). Paths are relative to the working directory.

## Native Android/iOS later

The Flutter UI is reusable, but this PoC ships a **web target**, not generated native projects. To add native scaffolding on a machine with the appropriate tooling:

```bash
flutter create --platforms=android,ios --project-name buggy_tracker .
```

Review generated changes and keep this project's `lib/` files, dependencies, and tests. Configure foreground location permissions following the [geolocator platform instructions](https://pub.dev/packages/geolocator): Android needs coarse/fine location permissions and internet permission in its main manifest; iOS needs a location usage description. Native builds also need an explicit reachable `API_BASE_URL`; prefer HTTPS. Native toolchains, signing, and platform configuration have not been validated here.

## PoC boundaries

This is a supervised lab demo, not a campus production service. There is one shared driver passphrase, no per-driver identity or ownership lock, and concurrent drivers for the same buggy overwrite each other. Anyone who can reach the server can read its latest locations. HTTP exposes the demo passphrase on the network, so use a unique demo-only value on a trusted network or HTTPS. State is held only in RAM; no location history is stored by the app. Background/locked-screen tracking, notifications, ETA prediction, multiple independent routes, reservations, and persistent storage are out of scope.

Tiles come from [OpenStreetMap](https://www.openstreetmap.org/copyright) and retain visible attribution. Follow the [tile usage policy](https://operations.osmfoundation.org/policies/tiles/) for any deployment; do not bulk-download tiles or use this public endpoint for a large rollout. Package API references: [flutter_map](https://pub.dev/packages/flutter_map), [geolocator](https://pub.dev/packages/geolocator), and [http](https://pub.dev/packages/http).

