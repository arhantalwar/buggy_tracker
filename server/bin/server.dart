import 'dart:convert';
import 'dart:io';
import '../lib/tracker.dart';

Future<void> main() async {
    final env = Platform.environment;
    final key = env['DRIVER_KEY'];
    if (key == null || key.trim().length < 8) {
        stderr.writeln('Set DRIVER_KEY to a demo passphrase of at least 8 characters.');
        exitCode = 64;
        return;
    }
    final tracker = Tracker(jsonDecode(await File(
                    env['CAMPUS_CONFIG'] ?? 'config/campus.json',
                    ).readAsString()) as Map<String, dynamic>);
    final root = Directory(env['WEB_ROOT'] ?? 'build/web').absolute.path;
    final server = await HttpServer.bind(
            env['HOST'] ?? '0.0.0.0', int.parse(env['PORT'] ?? '8080'),
            );
    stdout.writeln('Buggy Tracker listening on port ${server.port}');
    await for (final request in server) {
        // Each request handles its own errors without terminating the server.
        handle(request, tracker, key, root);
    }
}

void jsonReply(HttpResponse response, int status, Object data) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.headers.set('Cache-Control', 'no-store');
    response.write(jsonEncode(data));
}

Future<void> handle(HttpRequest request, Tracker tracker, String key, String root) async {
    final response = request.response;
    // CORS permits Flutter's separate development web server. No cookies used.
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, PUT, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', 'Content-Type, X-Driver-Key');
    try {
        final path = request.uri.path;
        if (request.method == 'OPTIONS') {
            response.statusCode = 204;
        } else if (path == '/api/state' && request.method == 'GET') {
            jsonReply(response, 200, tracker.snapshot());
        } else if ((path.startsWith('/api/buggies/') || path == '/api/route') && request.method == 'PUT') {
            if (request.headers.value('X-Driver-Key') != key) {
                jsonReply(response, 401, {'error': 'Incorrect driver passphrase'});
            } else {
                final bytes = <int>[];
                await for (final chunk in request.timeout(const Duration(seconds: 5))) {
                    bytes.addAll(chunk);
                    if (bytes.length > 4096) throw FormatException('Request too large');
                }
                final input = jsonDecode(utf8.decode(bytes));
                if (input is! Map<String, dynamic>) throw FormatException('Expected JSON object');
                if (path == '/api/route') {
                    tracker.moveDemoRoute(input);
                } else {
                    tracker.update(request.uri.pathSegments.last, input);
                }
                jsonReply(response, 200, tracker.snapshot());
            }
        } else if (path.startsWith('/api/')) {
            jsonReply(response, 404, {'error': 'Unknown API endpoint'});
        } else if (request.method == 'GET') {
            final segments = request.uri.pathSegments;
            if (segments.any((s) => s == '..' || s.contains('\\') || s.contains('/'))) {
                jsonReply(response, 400, {'error': 'Invalid path'});
            } else {
                final relative = path == '/' ? 'index.html' : segments.join('/');
                final file = File('$root/$relative');
                if (!await file.exists()) {
                    jsonReply(response, 404, {'error': 'File not found. Run flutter build web first.'});
                } else {
                    const types = {
                        'html': 'text/html; charset=utf-8', 'js': 'application/javascript',
                        'json': 'application/json', 'css': 'text/css', 'wasm': 'application/wasm',
                        'png': 'image/png', 'svg': 'image/svg+xml', 'ico': 'image/x-icon',
                        'woff2': 'font/woff2', 'ttf': 'font/ttf',
                    };
                    response.headers.set('Content-Type', types[relative.split('.').last] ?? 'application/octet-stream');
                    response.headers.set('Cache-Control', 'no-cache');
                    await response.addStream(file.openRead());
                }
            }
        } else {
            jsonReply(response, 405, {'error': 'Method not allowed'});
        }
    } on FormatException catch (error) {
        jsonReply(response, 400, {'error': error.message});
    } catch (error) {
        stderr.writeln('Request failed: $error');
        jsonReply(response, 500, {'error': 'Request failed'});
    } finally {
        await response.close();
    }
}
