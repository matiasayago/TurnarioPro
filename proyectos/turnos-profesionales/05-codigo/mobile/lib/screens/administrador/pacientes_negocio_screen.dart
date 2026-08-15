import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';
import 'ficha_paciente_negocio_screen.dart';

/// Pacientes del Negocio (Panel Administrador) — fast-follow de la épica E15 "Modo Administrador
/// v1" (`02-backlog/backlog.md`, entrada "Fast-follow — acceso de administrador al historial de
/// pacientes", 2026-08-15). Acceso de SOLO LECTURA: el administrador puede ver el historial
/// clínico de los pacientes de su negocio, pero la escritura (crear/editar ficha, tratamiento,
/// nota médica) sigue siendo exclusiva del profesional dueño de la ficha (autoría clínica,
/// implicancia médico-legal — RN7/RN13/D3, `documento-funcional.md` §3) — por eso, a propósito,
/// esta pantalla no tiene ningún botón de alta/edición, a diferencia de sus hermanas
/// `servicios_negocio_screen.dart`/`profesionales_negocio_screen.dart`.
///
/// Contrato: `GET /negocios/:id/pacientes` (`requireAuth('administrador')`) -> 200 array de
/// `{ ficha_id, id, nombre, email, telefono, profesional_id, profesional_nombre, activo, es_nuevo,
/// es_reciente, ultima_visita }` (ver `backend/src/routes/negocios.ts`, bloque "Acceso de
/// administrador al historial de pacientes").
///
/// **Una fila por FICHA, no por persona**: la misma persona atendida por 2 profesionales de este
/// negocio aparece 2 veces (cada ficha es independiente, con sus propios datos clínicos —
/// `UNIQUE (negocio_id, profesional_id, cliente_id)`) — a propósito NO se fusionan acá. Por eso
/// cada fila muestra explícitamente `profesional_nombre` (quién la atendió): es el dato que
/// distingue una ficha de otra cuando el nombre del paciente se repite, y es la diferencia clave
/// contra `profesional/gestion_pacientes_screen.dart` (que no lo necesita — ahí sólo hay un
/// profesional posible, el dueño de la sesión).
///
/// Esta pantalla NO reutiliza `GestionPacientesScreen` ni su modelo `_Paciente`: el contrato de acá
/// es distinto (`ficha_id` en vez de `cliente_id` como clave de navegación, más `profesional_id`/
/// `profesional_nombre`) y esa pantalla está acoplada a `sesion.profesionalId` en el path del
/// endpoint. Se sigue el mismo criterio de "cada pantalla define sus propios modelos/widgets
/// privados" que el resto del código (ver `servicios_negocio_screen.dart`).
///
/// Sin buscador/filtros ni resumen de contadores (a diferencia de `GestionPacientesScreen`, que sí
/// los tiene por HU-19): no fueron pedidos para esta ronda y el endpoint ya devuelve la lista
/// ordenada por nombre — se puede sumar después sin romper este contrato si hiciera falta.
class PacientesNegocioScreen extends StatefulWidget {
  const PacientesNegocioScreen({super.key});

  @override
  State<PacientesNegocioScreen> createState() => _PacientesNegocioScreenState();
}

class _PacientesNegocioScreenState extends State<PacientesNegocioScreen> {
  late Future<List<_PacienteNegocio>> _futurePacientes;

  @override
  void initState() {
    super.initState();
    // Mismo guard defensivo que `ProfesionalesNegocioScreen`/`ServiciosNegocioScreen`: en la
    // práctica esta pantalla sólo es alcanzable desde `AdministradorShell` cuando ya hay
    // `negocioId` (el ítem de menú vive dentro del `if (sesion.negocioId == null) ... else`), pero
    // se mantiene el mismo chequeo por si el criterio de esa pantalla cambia más adelante.
    final sesion = context.read<Sesion>();
    _futurePacientes = sesion.negocioId == null
        ? Future.error(Exception('No se pudo determinar tu negocio (falta negocio_id en la sesión).'))
        : _cargar();
  }

  Future<List<_PacienteNegocio>> _cargar() async {
    final sesion = context.read<Sesion>();
    final raw = await sesion.api.getList('/negocios/${sesion.negocioId}/pacientes');
    return raw.map((e) => _PacienteNegocio.fromApi(e as Map<String, dynamic>)).toList();
  }

  Future<void> _refrescar() async {
    final next = _cargar();
    setState(() => _futurePacientes = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(
        variant: AppHeaderVariant.surface,
        emoji: '🏥',
        title: 'Pacientes del Negocio',
        showBackButton: true,
      ),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<List<_PacienteNegocio>>(
          future: _futurePacientes,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Center(
                    child: Text(
                      'No se pudo cargar la lista de pacientes: ${snapshot.error}',
                      style: AppTypography.body(context),
                    ),
                  ),
                ],
              );
            }

            final pacientes = snapshot.data ?? [];
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                if (pacientes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Center(
                      child: Text(
                        'Todavía no hay pacientes registrados en este negocio.',
                        textAlign: TextAlign.center,
                        style: AppTypography.body(context),
                      ),
                    ),
                  )
                else
                  for (final paciente in pacientes) ...[
                    _PacienteNegocioCard(paciente: paciente),
                    const SizedBox(height: AppSpacing.md),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PacienteNegocio {
  const _PacienteNegocio({
    required this.fichaId,
    required this.nombre,
    required this.email,
    required this.telefono,
    required this.profesionalNombre,
    required this.activo,
    required this.ultimaVisita,
  });

  /// `paciente.id` — clave de navegación hacia `FichaPacienteNegocioScreen`
  /// (`GET /negocios/:id/pacientes/:fichaId`), NO `usuario.id` (ese es el `id` suelto que también
  /// devuelve la API pero que acá no hace falta guardar).
  final String fichaId;
  final String nombre;
  final String email;
  final String? telefono;
  final String profesionalNombre;
  final bool activo;
  final DateTime? ultimaVisita;

  factory _PacienteNegocio.fromApi(Map<String, dynamic> json) {
    final ultimaVisitaRaw = json['ultima_visita'] as String?;
    return _PacienteNegocio(
      fichaId: json['ficha_id'] as String,
      nombre: json['nombre'] as String,
      email: json['email'] as String,
      telefono: json['telefono'] as String?,
      profesionalNombre: json['profesional_nombre'] as String,
      activo: json['activo'] as bool,
      ultimaVisita: ultimaVisitaRaw != null ? DateTime.parse(ultimaVisitaRaw).toLocal() : null,
    );
  }
}

/// Fila de paciente: nombre + `StatusPill.activo`, a quién atendió (`profesional_nombre` — el dato
/// que esta vista de administrador agrega sobre la del profesional, ver comentario de la
/// pantalla), email, teléfono (si no es null) y última visita. Toda la card es tappeable (sin fila
/// de acciones Ver/Editar/Historial como `GestionPacientesScreen`: acá sólo hay UN destino
/// posible, el detalle de solo lectura) — mismo criterio visual que `_MenuTile`
/// (`administrador_shell.dart`): ícono `chevron_right` a la derecha como única señal de
/// navegación.
class _PacienteNegocioCard extends StatelessWidget {
  const _PacienteNegocioCard({required this.paciente});

  final _PacienteNegocio paciente;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final ultimaVisitaTexto = paciente.ultimaVisita != null
        ? DateFormat('d MMM yyyy', 'es').format(paciente.ultimaVisita!)
        : 'Sin visitas registradas';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        // Mismo criterio que `GestionPacientesScreen`/`_PacienteCard`: fondo levemente distinto
        // para fichas inactivas.
        color: paciente.activo ? colors.surface : colors.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppRadius.cardShadow,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FichaPacienteNegocioScreen(fichaId: paciente.fichaId, pacienteNombre: paciente.nombre),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            paciente.nombre,
                            style: AppTypography.subtitle(context)
                                .copyWith(color: colors.textPrimary, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        StatusPill.activo(paciente.activo),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Icon(Icons.badge_outlined, size: 14, color: colors.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Atendido por ${paciente.profesionalNombre}',
                            style: AppTypography.caption(context).copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(paciente.email, style: AppTypography.caption(context)),
                    if (paciente.telefono != null) ...[
                      const SizedBox(height: 2),
                      Text(paciente.telefono!, style: AppTypography.caption(context)),
                    ],
                    const SizedBox(height: 2),
                    Text('Última visita: $ultimaVisitaTexto', style: AppTypography.caption(context)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.chevron_right, size: 20, color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
