import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../api_client.dart';

enum Rol { cliente, profesional, administrador }

/// Estado de sesión compartido por toda la app: token JWT + claims relevantes, usado para
/// decidir el modo de navegación (Cliente / Profesional) — ver
/// docs/04-diseno/mapa-pantallas.md §1. El JWT se decodifica una sola vez acá; las pantallas
/// no vuelven a tocar el token.
class Sesion extends ChangeNotifier {
  Sesion(this.api);

  final ApiClient api;
  String? token;
  Rol? rol;
  String? profesionalId;
  String? negocioId;

  bool get autenticado => token != null;

  void iniciarSesion(String token) {
    final claims = _decodificarClaims(token);
    this.token = token;
    rol = Rol.values.firstWhere((r) => r.name == claims['rol']);
    profesionalId = claims['profesional_id'] as String?;
    negocioId = claims['negocio_id'] as String?;
    api.setToken(token);
    notifyListeners();
  }

  void cerrarSesion() {
    token = null;
    rol = null;
    profesionalId = null;
    negocioId = null;
    api.setToken(null);
    notifyListeners();
  }

  Map<String, dynamic> _decodificarClaims(String token) {
    final payload = token.split('.')[1];
    final normalizado = base64Url.normalize(payload);
    return jsonDecode(utf8.decode(base64Url.decode(normalizado))) as Map<String, dynamic>;
  }
}
