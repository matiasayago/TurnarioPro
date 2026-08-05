import 'dart:convert';
import 'package:http/http.dart' as http;

/// Cliente HTTP fino sobre el backend (ver ../backend/README.md para levantarlo).
/// Base URL configurable: en un emulador Android, localhost del host es 10.0.2.2.
class ApiClient {
  ApiClient({this.baseUrl = 'http://10.0.2.2:3000'});

  final String baseUrl;
  String? _token;

  void setToken(String? token) => _token = token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<Map<String, dynamic>> _decode(http.Response res) async {
    final body = res.body.isNotEmpty ? jsonDecode(res.body) : {};
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, body['error']?.toString() ?? 'Error desconocido');
    }
    return body is Map<String, dynamic> ? body : {'data': body};
  }

  Future<dynamic> get(String path) async {
    final res = await http.get(Uri.parse('$baseUrl$path'), headers: _headers);
    if (res.statusCode >= 400) {
      final body = res.body.isNotEmpty ? jsonDecode(res.body) : {};
      throw ApiException(res.statusCode, body['error']?.toString() ?? 'Error desconocido');
    }
    return jsonDecode(res.body);
  }

  // Nota: NO se puede escribir `get(path) as Future<List<dynamic>>` en las pantallas — eso
  // castea el propio Future (falla en runtime), no el valor que resuelve. Estos dos helpers
  // esperan la respuesta y castean el valor ya resuelto, que es lo correcto.
  Future<List<dynamic>> getList(String path) async => (await get(path)) as List<dynamic>;

  Future<Map<String, dynamic>> getMap(String path) async => (await get(path)) as Map<String, dynamic>;

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final res = await http.post(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body));
    return _decode(res);
  }

  Future<Map<String, dynamic>> patch(String path, [Map<String, dynamic>? body]) async {
    final res = await http.patch(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body ?? {}));
    return _decode(res);
  }
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => message;
}
