import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';

final DateFormat _formatoFechaHora = DateFormat('d MMM yyyy · HH:mm', 'es');
final DateFormat _formatoFecha = DateFormat('d MMM yyyy', 'es');

String _formatoCosto(num? costo) => costo == null ? 'Sin costo definido' : '\$${costo.toStringAsFixed(0)}';

DateTime? _parseFechaSegura(String? raw) => raw == null ? null : DateTime.tryParse(raw)?.toLocal();

String _valorOTexto(String? valor) => (valor == null || valor.trim().isEmpty) ? 'Sin registrar' : valor.trim();

/// Detalle de Ficha de Paciente (Panel Administrador) — fast-follow de la épica E15 "Modo
/// Administrador v1" (`02-backlog/backlog.md`, entrada "Fast-follow — acceso de administrador al
/// historial de pacientes", 2026-08-15). SOLO LECTURA: a propósito no tiene ningún botón de
/// editar/crear (ni de ficha, ni de tratamiento, ni de nota médica) — la escritura sigue siendo
/// exclusiva del profesional dueño de la ficha (RN7/RN13/D3, autoría clínica con implicancia
/// médico-legal, `documento-funcional.md` §3, y policies RLS `FOR SELECT` únicamente — ver
/// `database/migrations/007_paciente_historial_acceso_administrador.sql`). No es un recorte de
/// alcance por tiempo: es una decisión de producto ya evaluada y tomada, no algo a reconsiderar acá.
///
/// A diferencia del lado profesional (`FichaPacienteScreen` + `HistorialPacienteScreen`, dos
/// pantallas separadas porque la primera necesita alternar a un modo "editar"), acá se combina
/// ficha + historial en UNA sola pantalla con scroll: sin edición no hay ningún motivo para
/// separarlas en dos navegaciones. Los 2 GET se piden en paralelo (`Future.wait`, ver [_cargar]):
/// son independientes entre sí, ninguno depende del resultado del otro.
///
/// Contrato (`backend/src/routes/negocios.ts`, bloque "Acceso de administrador al historial de
/// pacientes" — ver ahí el resto del razonamiento: filtros de aislamiento por negocio, RLS, etc.):
/// - `GET /negocios/:id/pacientes/:fichaId` -> 200 `{ id, nombre, email, telefono, ficha_id,
///   profesional_id, profesional_nombre, fecha_nacimiento, genero, direccion,
///   contacto_emergencia_nombre, contacto_emergencia_telefono, contacto_emergencia_relacion,
///   alergias, notas_medicas_generales, activo }` | 404 ficha inexistente/eliminada/de otro negocio.
/// - `GET /negocios/:id/pacientes/:fichaId/historial` -> 200 `{ paciente: {...}, resumen: {
///   citas_totales, citas_completadas, tratamientos, notas_medicas }, turnos: [...],
///   tratamientos: [...], notas_medicas: [...] }`. El campo `paciente` de esta respuesta se ignora
///   acá a propósito: es el mismo cliente (id/nombre/email/telefono/profesional_nombre) que ya
///   trae el primer GET — no hace falta parsearlo dos veces.
class FichaPacienteNegocioScreen extends StatefulWidget {
  const FichaPacienteNegocioScreen({super.key, required this.fichaId, required this.pacienteNombre});

  final String fichaId;

  /// Nombre ya conocido por la pantalla que navegó acá (`PacientesNegocioScreen`) — se usa como
  /// título del header mientras carga, para no mostrar un título vacío/genérico durante el
  /// `FutureBuilder` en estado `waiting` (mismo criterio que `FichaPacienteScreen`/
  /// `HistorialPacienteScreen` del lado profesional).
  final String pacienteNombre;

  @override
  State<FichaPacienteNegocioScreen> createState() => _FichaPacienteNegocioScreenState();
}

class _FichaPacienteNegocioScreenState extends State<FichaPacienteNegocioScreen> {
  late Future<_FichaDetalle> _future;

  @override
  void initState() {
    super.initState();
    // Mismo guard defensivo que el resto de las pantallas de este shell (`PacientesNegocioScreen`,
    // `ProfesionalesNegocioScreen`, `ServiciosNegocioScreen`).
    final sesion = context.read<Sesion>();
    _future = sesion.negocioId == null
        ? Future.error(Exception('No se pudo determinar tu negocio (falta negocio_id en la sesión).'))
        : _cargar();
  }

  Future<_FichaDetalle> _cargar() async {
    final sesion = context.read<Sesion>();
    final base = '/negocios/${sesion.negocioId}/pacientes/${widget.fichaId}';
    // Ambos GET son independientes (ninguno necesita el resultado del otro) — se piden en
    // paralelo con `Future.wait` en vez de uno tras otro, para no pagar 2 round-trips en serie.
    final resultados = await Future.wait([sesion.api.getMap(base), sesion.api.getMap('$base/historial')]);
    return _FichaDetalle(ficha: _Ficha.fromApi(resultados[0]), historial: _Historial.fromApi(resultados[1]));
  }

  Future<void> _refrescar() async {
    final next = _cargar();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(
        variant: AppHeaderVariant.surface,
        emoji: '👁️',
        title: widget.pacienteNombre,
        showBackButton: true,
      ),
      // Sin `bottomNavigationBar`/footer: a diferencia de `FichaPacienteScreen` (que necesita un
      // botón "Editar Paciente" para cambiar de modo), acá no hay ninguna acción que ofrecer — el
      // botón "Volver" del header ya alcanza para cerrar la pantalla.
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<_FichaDetalle>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Center(
                    child: Text('No se pudo cargar la ficha: ${snapshot.error}', style: AppTypography.body(context)),
                  ),
                ],
              );
            }

            final detalle = snapshot.data!;
            final ficha = detalle.ficha;
            final historial = detalle.historial;
            // "✱ Salud" sólo se muestra si hay algo cargado — a diferencia de `FichaPacienteScreen`
            // (lado profesional), que la oculta/muestra según `es_rubro_salud` del negocio (un GET
            // adicional a `/negocios`), acá se simplifica: en un negocio no-salud estos 2 campos
            // vienen vacíos, así que alcanza con chequear si hay contenido real para mostrar, sin
            // pagar una llamada extra sólo para decidir la visibilidad de una sección de solo
            // lectura.
            final tieneDatosDeSalud = (ficha.alergias?.trim().isNotEmpty ?? false) ||
                (ficha.notasMedicasGenerales?.trim().isNotEmpty ?? false);

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                _encabezado(context, ficha),
                const SizedBox(height: AppSpacing.lg),
                _sectionCard(
                  context,
                  title: 'Datos personales',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRow(context, 'Nombre', ficha.nombre),
                      _infoRow(context, 'Email', ficha.email),
                      _infoRow(context, 'Teléfono', _valorOTexto(ficha.telefono)),
                      _infoRow(
                        context,
                        'Fecha de nacimiento',
                        ficha.fechaNacimiento != null
                            ? DateFormat('dd/MM/yyyy').format(ficha.fechaNacimiento!)
                            : 'Sin registrar',
                      ),
                      _infoRow(context, 'Género', _valorOTexto(ficha.genero)),
                      _infoRow(context, 'Dirección', _valorOTexto(ficha.direccion), esUltimo: true),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _sectionCard(
                  context,
                  title: 'Contacto de emergencia',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRow(context, 'Nombre', _valorOTexto(ficha.contactoEmergenciaNombre)),
                      _infoRow(context, 'Teléfono', _valorOTexto(ficha.contactoEmergenciaTelefono)),
                      _infoRow(context, 'Relación', _valorOTexto(ficha.contactoEmergenciaRelacion), esUltimo: true),
                    ],
                  ),
                ),
                if (tieneDatosDeSalud) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _sectionCard(
                    context,
                    title: '✱ Salud',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _infoRow(context, 'Alergias', _valorOTexto(ficha.alergias)),
                        _infoRow(context, 'Notas médicas generales', _valorOTexto(ficha.notasMedicasGenerales),
                            esUltimo: true),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                Text('Historial', style: AppTypography.sectionTitle(context)),
                const SizedBox(height: AppSpacing.sm),
                StatCardGrid(cards: [
                  StatCard(
                    value: '${historial.resumen.citasTotales}',
                    label: 'Citas totales',
                    icon: Icons.event_outlined,
                  ),
                  StatCard(
                    value: '${historial.resumen.citasCompletadas}',
                    label: 'Completadas',
                    icon: Icons.check_circle_outline,
                    emphasize: true,
                  ),
                  StatCard(
                    value: '${historial.resumen.tratamientos}',
                    label: 'Tratamientos',
                    icon: Icons.healing_outlined,
                  ),
                  StatCard(
                    value: '${historial.resumen.notasMedicas}',
                    label: 'Notas médicas',
                    icon: Icons.notes_outlined,
                  ),
                ]),
                const SizedBox(height: AppSpacing.lg),
                Text('Turnos', style: AppTypography.sectionTitle(context)),
                const SizedBox(height: AppSpacing.sm),
                if (historial.turnos.isEmpty)
                  const _EstadoVacio(texto: 'Sin turnos registrados todavía.')
                else
                  for (final t in historial.turnos) ...[
                    _TurnoCard(turno: t),
                    const SizedBox(height: AppSpacing.md),
                  ],
                const SizedBox(height: AppSpacing.lg),
                Text('Tratamientos', style: AppTypography.sectionTitle(context)),
                const SizedBox(height: AppSpacing.sm),
                if (historial.tratamientos.isEmpty)
                  const _EstadoVacio(texto: 'Sin tratamientos registrados todavía.')
                else
                  for (final t in historial.tratamientos) ...[
                    _TratamientoCard(tratamiento: t),
                    const SizedBox(height: AppSpacing.md),
                  ],
                const SizedBox(height: AppSpacing.lg),
                Text('Notas médicas', style: AppTypography.sectionTitle(context)),
                const SizedBox(height: AppSpacing.sm),
                if (historial.notasMedicas.isEmpty)
                  const _EstadoVacio(texto: 'Sin notas médicas registradas todavía.')
                else
                  for (final n in historial.notasMedicas) ...[
                    _NotaMedicaCard(nota: n),
                    const SizedBox(height: AppSpacing.md),
                  ],
                const SizedBox(height: AppSpacing.xl),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Franja superior fija: quién atendió esta ficha (`profesional_nombre` — igual que en
  /// `PacientesNegocioScreen`, es el dato que un administrador con varios profesionales necesita
  /// confirmar antes de leer el resto) + el mismo `StatusPill.activo` que ya se ve en la lista.
  Widget _encabezado(BuildContext context, _Ficha ficha) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppRadius.cardShadow,
      ),
      child: Row(
        children: [
          Icon(Icons.badge_outlined, size: 18, color: colors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Atendido por ${ficha.profesionalNombre}',
              style: AppTypography.body(context).copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          StatusPill.activo(ficha.activo),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value, {bool esUltimo = false}) {
    final colors = AppColors.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: esUltimo ? 0 : AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.caption(context)),
          const SizedBox(height: 2),
          Text(value, style: AppTypography.body(context).copyWith(color: colors.textPrimary)),
        ],
      ),
    );
  }

  Widget _sectionCard(BuildContext context, {required String title, required Widget child}) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppRadius.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.sectionTitle(context)),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

/// Wrapper de los 2 GET que arma [_FichaPacienteNegocioScreenState._cargar] — sin equivalente en
/// el lado profesional (ahí son 2 pantallas separadas, cada una con su propio `Future` de un solo
/// shape).
class _FichaDetalle {
  const _FichaDetalle({required this.ficha, required this.historial});

  final _Ficha ficha;
  final _Historial historial;
}

class _Ficha {
  const _Ficha({
    required this.nombre,
    required this.email,
    required this.telefono,
    required this.profesionalNombre,
    required this.fechaNacimiento,
    required this.genero,
    required this.direccion,
    required this.contactoEmergenciaNombre,
    required this.contactoEmergenciaTelefono,
    required this.contactoEmergenciaRelacion,
    required this.alergias,
    required this.notasMedicasGenerales,
    required this.activo,
  });

  final String nombre;
  final String email;
  final String? telefono;
  final String profesionalNombre;
  final DateTime? fechaNacimiento;
  final String? genero;
  final String? direccion;
  final String? contactoEmergenciaNombre;
  final String? contactoEmergenciaTelefono;
  final String? contactoEmergenciaRelacion;
  final String? alergias;
  final String? notasMedicasGenerales;
  final bool activo;

  factory _Ficha.fromApi(Map<String, dynamic> json) {
    final fechaNacimientoRaw = json['fecha_nacimiento'] as String?;
    return _Ficha(
      nombre: json['nombre'] as String,
      email: json['email'] as String,
      telefono: json['telefono'] as String?,
      profesionalNombre: json['profesional_nombre'] as String,
      fechaNacimiento: fechaNacimientoRaw != null ? DateTime.parse(fechaNacimientoRaw) : null,
      genero: json['genero'] as String?,
      direccion: json['direccion'] as String?,
      contactoEmergenciaNombre: json['contacto_emergencia_nombre'] as String?,
      contactoEmergenciaTelefono: json['contacto_emergencia_telefono'] as String?,
      contactoEmergenciaRelacion: json['contacto_emergencia_relacion'] as String?,
      alergias: json['alergias'] as String?,
      notasMedicasGenerales: json['notas_medicas_generales'] as String?,
      activo: json['activo'] as bool,
    );
  }
}

class _Historial {
  const _Historial({
    required this.resumen,
    required this.turnos,
    required this.tratamientos,
    required this.notasMedicas,
  });

  final _Resumen resumen;
  final List<_Turno> turnos;
  final List<_Tratamiento> tratamientos;
  final List<_NotaMedica> notasMedicas;

  factory _Historial.fromApi(Map<String, dynamic> json) {
    return _Historial(
      resumen: _Resumen.fromApi(json['resumen'] as Map<String, dynamic>),
      turnos: (json['turnos'] as List<dynamic>).map((e) => _Turno.fromApi(e as Map<String, dynamic>)).toList(),
      tratamientos:
          (json['tratamientos'] as List<dynamic>).map((e) => _Tratamiento.fromApi(e as Map<String, dynamic>)).toList(),
      notasMedicas:
          (json['notas_medicas'] as List<dynamic>).map((e) => _NotaMedica.fromApi(e as Map<String, dynamic>)).toList(),
    );
  }
}

class _Resumen {
  const _Resumen({
    required this.citasTotales,
    required this.citasCompletadas,
    required this.tratamientos,
    required this.notasMedicas,
  });

  final int citasTotales;
  final int citasCompletadas;
  final int tratamientos;
  final int notasMedicas;

  factory _Resumen.fromApi(Map<String, dynamic> json) => _Resumen(
        citasTotales: json['citas_totales'] as int,
        citasCompletadas: json['citas_completadas'] as int,
        tratamientos: json['tratamientos'] as int,
        notasMedicas: json['notas_medicas'] as int,
      );
}

class _Turno {
  const _Turno({
    required this.inicio,
    required this.estadoPago,
    required this.servicio,
    required this.costo,
    required this.profesional,
    required this.duracionMin,
  });

  final DateTime inicio;
  final TurnoEstado estadoPago;
  final String servicio;
  final num? costo;
  final String profesional;
  final int duracionMin;

  factory _Turno.fromApi(Map<String, dynamic> json) => _Turno(
        inicio: DateTime.parse(json['inicio'] as String).toLocal(),
        estadoPago: turnoEstadoFromApi(json['estado_pago'] as String),
        servicio: json['servicio'] as String,
        costo: json['costo'] as num?,
        profesional: json['profesional'] as String,
        duracionMin: json['duracion_min'] as int,
      );
}

class _Tratamiento {
  const _Tratamiento({required this.descripcion, required this.fechaInicio, required this.fechaFin});

  final String descripcion;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;

  factory _Tratamiento.fromApi(Map<String, dynamic> json) => _Tratamiento(
        descripcion: json['descripcion'] as String,
        fechaInicio: _parseFechaSegura(json['fecha_inicio'] as String?),
        fechaFin: _parseFechaSegura(json['fecha_fin'] as String?),
      );
}

class _NotaMedica {
  const _NotaMedica({required this.fecha, required this.texto});

  final DateTime? fecha;
  final String texto;

  factory _NotaMedica.fromApi(Map<String, dynamic> json) => _NotaMedica(
        fecha: _parseFechaSegura(json['fecha'] as String?),
        texto: json['texto'] as String,
      );
}

class _TurnoCard extends StatelessWidget {
  const _TurnoCard({required this.turno});

  final _Turno turno;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppRadius.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _formatoFechaHora.format(turno.inicio),
                  style:
                      AppTypography.subtitle(context).copyWith(color: colors.textPrimary, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusPill.turno(turno.estadoPago),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(turno.servicio, style: AppTypography.body(context)),
          const SizedBox(height: 2),
          Text(
            'Profesional: ${turno.profesional} · Duración: ${turno.duracionMin} min',
            style: AppTypography.caption(context),
          ),
          const SizedBox(height: 2),
          Text('Costo: ${_formatoCosto(turno.costo)}', style: AppTypography.caption(context)),
        ],
      ),
    );
  }
}

class _TratamientoCard extends StatelessWidget {
  const _TratamientoCard({required this.tratamiento});

  final _Tratamiento tratamiento;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final inicio =
        tratamiento.fechaInicio != null ? _formatoFecha.format(tratamiento.fechaInicio!) : 'fecha no informada';
    final finTexto =
        tratamiento.fechaFin != null ? ' · Finalizado ${_formatoFecha.format(tratamiento.fechaFin!)}' : ' · En curso';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppRadius.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tratamiento.descripcion, style: AppTypography.body(context).copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('Iniciado $inicio$finTexto', style: AppTypography.caption(context)),
        ],
      ),
    );
  }
}

class _NotaMedicaCard extends StatelessWidget {
  const _NotaMedicaCard({required this.nota});

  final _NotaMedica nota;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fecha = nota.fecha != null ? _formatoFecha.format(nota.fecha!) : 'Fecha no informada';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppRadius.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(fecha, style: AppTypography.caption(context).copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(nota.texto, style: AppTypography.body(context)),
        ],
      ),
    );
  }
}

class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) => Text(texto, style: AppTypography.caption(context));
}
