import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'api_client.dart';
import 'state/sesion.dart';
import 'state/theme_controller.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/administrador/administrador_shell.dart';
import 'screens/cliente/cliente_shell.dart';
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

/// Punto único de decisión de modo — Cliente, Profesional o Administrador, según el ÚNICO rol de
/// la sesión (ver docs/04-diseno/mapa-pantallas.md §1 y `02-backlog/backlog.md` E15 "Preguntas
/// abiertas": `usuario.rol` es un único valor, una misma cuenta nunca es Profesional y
/// Administrador a la vez, así que no hay selector "actuar como" — cada cuenta entra a exactamente
/// un shell, no intercambiable).
class _Router extends StatelessWidget {
  const _Router();

  @override
  Widget build(BuildContext context) {
    final sesion = context.watch<Sesion>();
    if (!sesion.autenticado) return const LoginScreen();
    switch (sesion.rol) {
      case Rol.cliente:
        return const ClienteShell();
      case Rol.profesional:
        // HU-27 ("cambiar de vista"): `key` atada al negocio activo, no `const`. Cada pantalla
        // del lado Profesional cachea su propio Future en `initState` (no reacciona sola a
        // cambios de `Sesion` — ver `profesional/dashboard_screen.dart`), así que cambiar de
        // negocio (`Sesion.entrarANegocio`) necesita recrear todo este subárbol desde cero para
        // que cada pestaña vuelva a pedir sus datos ya scopeados al negocio nuevo. Sin cambio de
        // negocio (caso común, un solo negocio o ninguno) esta key es constante durante toda la
        // sesión — cero cambio de comportamiento respecto de antes de esta historia.
        return ProfesionalShell(key: ValueKey(sesion.negocioId));
      case Rol.administrador:
        // HU-36 (épica E15 "Modo Administrador v1", `02-backlog/backlog.md`): shell propio del
        // rol administrador — mismo criterio de `key` atada al negocio activo que `ProfesionalShell`
        // arriba (HU-27: cambiar de negocio recrea el shell desde cero, ver
        // `AdministradorShell._cambiarNegocio`).
        return AdministradorShell(key: ValueKey(sesion.negocioId));
      case null:
        return const LoginScreen();
    }
  }
}
