import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

class TrackerApi {
    TrackerApi(String base) : base = base.replaceFirst(RegExp(r'/+$'), '');
    final String base;
    final http.Client _client = http.Client();

    Future<Snapshot> read() async => _decode(await _client.get(
                Uri.parse('$base/api/state'),
                ).timeout(const Duration(seconds: 5)));

    Future<Snapshot> write(String path, String key, Map<String, dynamic> data) async =>
        _decode(await _client.put(Uri.parse('$base/api/$path'), headers: {
                    'Content-Type': 'application/json', 'X-Driver-Key': key,
                    }, body: jsonEncode(data)).timeout(const Duration(seconds: 5)));

    Snapshot _decode(http.Response response) {
        if (response.statusCode != 200) {
            throw Exception('Server ${response.statusCode}: ${response.body}');
        }
        return Snapshot(jsonDecode(response.body) as Map<String, dynamic>);
    }

    void dispose() => _client.close();
}
