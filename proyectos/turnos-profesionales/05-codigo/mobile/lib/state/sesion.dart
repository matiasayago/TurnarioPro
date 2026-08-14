import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../api_client.dart';

enum Rol { cliente, profesional, administrador }

/// Una fila de la lista `negocios` que devuelve `POST /auth/login`/`POST /auth/google` cuando el
/// usuario autenticado (profesional o administrador) tiene 0 o 2+ negocios con membresía activa
/// — ver `responderLoginConNegocios` en `../backend/src/routes/auth.ts` y HU-27 ("cambiar de
/// vista", `02-backlog/backlog.md`). Con exactamente 1 negocio el backend NO manda esta lista
/// (el `negocio_id` ya viene resuelto directo en el token) — caso común, sin cambios.
@immutable
class NegocioMembresia {
  const NegocioMembresia({required this.negocioId, required this.nombre, required this.rol});

  final String negocioId;
  final String nombre;

  /// Rol del usuario autenticado, no de este negocio en particular — `usuario.rol` es un único
  /// valor global (el backend repite el mismo `claimsBase.rol` en cada fila, ver
  /// `responderLoginConNegocios`). Se guarda igual por si una pantalla futura lo necesita; el
  /// selector de esta historia no lo muestra (alcanza con el nombre, ver HU-27).
  final String rol;

  factory NegocioMembresia.fromApi(Map<String, dynamic> json) => NegocioMembresia(
        negocioId: json['negocio_id'] as String,
        nombre: json['nombre'] as String,
        rol: json['rol'] as String,
      );
}

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

  /// Email de la sesión activa — NO viaja en el JWT (ver `auth.ts`: `signToken` solo pone
  /// `sub`/`rol`/`negocio_id`/`profesional_id`), así que no se puede decodificar del token como
  /// el resto de estos campos. Se recibe como parámetro opcional de [iniciarSesion] con el mismo
  /// valor que el usuario ya tipeó para loguearse (`login_screen.dart`) — precisa y no inventada,
  /// a diferencia de un `nombre` que la app no tiene forma de conocer todavía (mismo motivo por
  /// el que `dashboard_screen.dart` evita fabricar uno, ver su comentario "¡Hola!").
  String? email;

  /// HU-27 ("cambiar de vista"): negocios activos del usuario autenticado, tal como los devolvió
  /// `POST /auth/login`/`POST /auth/google` (ver [NegocioMembresia]) — se guarda acá una única
  /// vez, en el login, para que el ícono "cambiar de vista" del Dashboard
  /// (`screens/profesional/dashboard_screen.dart`) lo reutilice sin volver a pedirlo (no hay
  /// endpoint propio de "mis negocios"). Vacía en el caso común (1 solo negocio, ya resuelto
  /// directo en el token, o rol cliente sin negocio) — ver [tieneMultiplesNegocios].
  List<NegocioMembresia> negocios = [];

  /// El selector de "cambiar de vista" solo tiene sentido con 2+ negocios entre los que elegir.
  bool get tieneMultiplesNegocios => negocios.length >= 2;

  bool get autenticado => token != null;

  /// Decodifica [token] y actualiza los claims de la sesión. [email]/[negocios] son opcionales y
  /// SOLO pisan el valor ya guardado cuando se pasan explícitos (no nulos) — así, al cambiar de
  /// negocio con la sesión ya iniciada (ver [entrarANegocio]), alcanza con reemitir el token sin
  /// tener que repetir el email ni la lista de negocios, que no cambiaron.
  void iniciarSesion(String token, {String? email, List<NegocioMembresia>? negocios}) {
    final claims = _decodificarClaims(token);
    this.token = token;
    this.email = email ?? this.email;
    rol = Rol.values.firstWhere((r) => r.name == claims['rol']);
    profesionalId = claims['profesional_id'] as String?;
    negocioId = claims['negocio_id'] as String?;
    if (negocios != null) this.negocios = negocios;
    api.setToken(token);
    notifyListeners();
  }

  /// HU-27 ("cambiar de vista"): pide `POST /auth/entrar-a-negocio` para [negocioId] y reemite la
  /// sesión con el token que devuelve (ya con ese negocio en el claim, ver [iniciarSesion]). Dos
  /// llamadores, mismo endpoint:
  /// - `login_screen.dart`, cuando la cuenta recién autenticada tiene 2+ negocios activos y
  ///   todavía no hay uno elegido: la sesión no está iniciada todavía (`api` no tiene token
  ///   seteado), así que hace falta pasar [tokenPrevio] (el token recién recibido de
  ///   `/auth/login`, válido para autenticar este endpoint aunque no tenga `negocio_id` — ver
  ///   `requireAuth()` sin roles en `auth.ts`) y [email]/[negocios] (para que [iniciarSesion] los
  ///   guarde por primera vez).
  /// - `screens/profesional/dashboard_screen.dart`, para cambiar de negocio con la sesión ya
  ///   iniciada: no hace falta ninguno de los tres — `api` ya tiene un token válido, y
  ///   [email]/los negocios disponibles no cambiaron.
  Future<void> entrarANegocio(
    String negocioId, {
    String? tokenPrevio,
    String? email,
    List<NegocioMembresia>? negocios,
  }) async {
    if (tokenPrevio != null) api.setToken(tokenPrevio);
    final resp = await api.post('/auth/entrar-a-negocio', {'negocio_id': negocioId});
    iniciarSesion(resp['token'] as String, email: email, negocios: negocios);
  }

  void cerrarSesion() {
    token = null;
    email = null;
    rol = null;
    profesionalId = null;
    negocioId = null;
    negocios = [];
    api.setToken(null);
    notifyListeners();
  }

  Map<String, dynamic> _decodificarClaims(String token) {
    final payload = token.split('.')[1];
    final normalizado = base64Url.normalize(payload);
    return jsonDecode(utf8.decode(base64Url.decode(normalizado))) as Map<String, dynamic>;
  }
}
