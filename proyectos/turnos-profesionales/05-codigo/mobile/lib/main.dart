import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'api_client.dart';
import 'state/sesion.dart';
import 'state/theme_controller.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/cliente/buscar_negocios_screen.dart';
import 'screens/profesional/profesional_shell.dart';

void main() async {
  // Requerido por `intl` antes de usar DateFormat con locale 'es' (ver pantallas de
  // horarios/agenda/historial) — si se omite, DateFormat tira LocaleDataException en runtime.
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');

  final api = ApiClient();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => Sesion(api)),
        ChangeNotifierProvider(create: (_) => ThemeController()),
      ],
      child: const TurnosProfesionalesApp(),
    ),
  );
}

class TurnosProfesionalesApp extends StatelessWidget {
  const TurnosProfesionalesApp({super.key});

  @override
  Widget build(BuildContext context) {
    // sistema-diseno.md §8: tema claro/oscuro alternable sin reiniciar la app (ThemeController
    // notifica, MaterialApp se reconstruye) y respeta la preferencia del sistema por defecto
    // (ThemeController arranca en ThemeMode.system).
    final themeMode = context.watch<ThemeController>().mode;
    return MaterialApp(
      title: 'Turnos Profesionales',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const _Router(),
    );
  }
}

/// Punto único de decisión de modo: Cliente vs. Profesional, según el rol de la sesión
/// (ver docs/04-diseno/mapa-pantallas.md §1 — una sola app, dos modos, no intercambiable).
class _Router extends StatelessWidget {
  const _Router();

  @override
  Widget build(BuildContext context) {
    final sesion = context.watch<Sesion>();
    if (!sesion.autenticado) return const LoginScreen();
    switch (sesion.rol) {
      case Rol.cliente:
        return const BuscarNegociosScreen();
      case Rol.profesional:
        return const ProfesionalShell();
      case Rol.administrador:
      case null:
        // El administrador gestiona el negocio; en este slice de mobile no tiene pantallas
        // propias todavía (queda para una fase posterior, ver README.md de este proyecto).
        return const LoginScreen();
    }
  }
}
