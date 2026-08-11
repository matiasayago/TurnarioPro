import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';
import 'ficha_paciente_screen.dart';
import 'historial_paciente_screen.dart';

/// Gestión de Pacientes (Profesional) — HU-10 + HU-19, reemplaza a `MisClientesScreen` dentro
/// del `ProfesionalShell` (wireframe corregido en `mapa-pantallas.md` §5.8bis, reconciliado
/// contra capturas reales). A propósito NO incluye: "Agregar Paciente" manual (no hay endpoint —
/// el modelo exige que un paciente tenga al menos un turno con este profesional antes de existir
/// su ficha), "Importar"/"Exportar" (HU-22, diferida hasta luz verde de Security — ver
/// backlog.md), acción "Agendar" por fila (el modal de "Agendar Cita manual" es de otra ronda),
/// "Contactar" (no confirmado contra capturas reales) ni FAB (confirmado que no existe).
///
/// Todo el filtrado (buscador + chips Todos/Activos/Inactivos/Recientes) es 100% client-side
/// sobre el único array que devuelve `GET /profesionales/:id/clientes` — no hay endpoint de
/// agregados separado, los 4 contadores del resumen también se calculan acá.
class GestionPacientesScreen extends StatefulWidget {
  const GestionPacientesScreen({super.key});

  @override
  State<GestionPacientesScreen> createState() => _GestionPacientesScreenState();
}

enum _FiltroPaciente { todos, activos, inactivos, recientes }

String _filtroLabel(_FiltroPaciente f) => switch (f) {
      _FiltroPaciente.todos => 'Todos',
      _FiltroPaciente.activos => 'Activos',
      _FiltroPaciente.inactivos => 'Inactivos',
      _FiltroPaciente.recientes => 'Recientes',
    };

class _GestionPacientesScreenState extends State<GestionPacientesScreen> {
  late Future<List<_Paciente>> _futurePacientes;
  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';
  _FiltroPaciente _filtro = _FiltroPaciente.todos;

  @override
  void initState() {
    super.initState();
    _futurePacientes = _cargar();
    _busquedaCtrl.addListener(() {
      setState(() => _busqueda = _busquedaCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<List<_Paciente>> _cargar() async {
    final sesion = context.read<Sesion>();
    final raw = await sesion.api.getList('/profesionales/${sesion.profesionalId}/clientes');
    return raw.map((e) => _Paciente.fromApi(e as Map<String, dynamic>)).toList();
  }

  Future<void> _refrescar() async {
    final next = _cargar();
    setState(() => _futurePacientes = next);
    await next;
  }

  List<_Paciente> _filtrar(List<_Paciente> pacientes) {
    return pacientes.where((p) {
      if (_busqueda.isNotEmpty && !p.nombre.toLowerCase().contains(_busqueda)) return false;
      switch (_filtro) {
        case _FiltroPaciente.todos:
          return true;
        case _FiltroPaciente.activos:
          return p.activo;
        case _FiltroPaciente.inactivos:
          return !p.activo;
        case _FiltroPaciente.recientes:
          return p.esReciente;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(
        variant: AppHeaderVariant.primary,
        emoji: '🏥',
        title: 'Gestión de Pacientes',
        subtitle: 'Administra tu lista de pacientes',
      ),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<List<_Paciente>>(
          future: _futurePacientes,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
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
            final visibles = _filtrar(pacientes);

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                _ResumenPacientesCard(pacientes: pacientes),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _busquedaCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Buscar pacientes...',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final f in _FiltroPaciente.values)
                      _FiltroChip(
                        label: _filtroLabel(f),
                        selected: _filtro == f,
                        onTap: () => setState(() => _filtro = f),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                if (pacientes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Center(
                      child: Text('Todavía no atendiste a ningún paciente.', style: AppTypography.body(context)),
                    ),
                  )
                else if (visibles.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Center(
                      child: Text(
                        'Ningún paciente coincide con la búsqueda/filtro.',
                        style: AppTypography.body(context),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  for (final p in visibles) ...[
                    _PacienteCard(paciente: p),
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

class _Paciente {
  const _Paciente({
    required this.id,
    required this.nombre,
    required this.email,
    required this.telefono,
    required this.activo,
    required this.esNuevo,
    required this.esReciente,
    required this.ultimaVisita,
  });

  final String id;
  final String nombre;
  final String email;
  final String? telefono;
  final bool activo;
  final bool esNuevo;
  final bool esReciente;
  final DateTime? ultimaVisita;

  factory _Paciente.fromApi(Map<String, dynamic> json) {
    final ultimaVisitaRaw = json['ultima_visita'] as String?;
    return _Paciente(
      id: json['id'] as String,
      nombre: json['nombre'] as String,
      email: json['email'] as String,
      telefono: json['telefono'] as String?,
      activo: json['activo'] as bool,
      esNuevo: json['es_nuevo'] as bool,
      esReciente: json['es_reciente'] as bool,
      ultimaVisita: ultimaVisitaRaw != null ? DateTime.parse(ultimaVisitaRaw).toLocal() : null,
    );
  }
}

/// §5.8bis: "1 sola card, 4 columnas" — a diferencia de `StatCardGrid` (varias cards separadas,
/// cada una con su propia sombra), acá los 4 números viven dentro de un único contenedor. Se
/// arma ad-hoc en vez de reutilizar `StatCard` porque ese widget siempre se dibuja a sí mismo
/// como card independiente (fondo + sombra propios) — no expone una variante "solo contenido".
class _ResumenPacientesCard extends StatelessWidget {
  const _ResumenPacientesCard({required this.pacientes});

  final List<_Paciente> pacientes;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final total = pacientes.length;
    final activos = pacientes.where((p) => p.activo).length;
    final inactivos = total - activos;
    final nuevos = pacientes.where((p) => p.esNuevo).length;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppRadius.cardShadow,
      ),
      child: Row(
        children: [
          Expanded(child: _Columna(valor: '$total', label: 'TOTAL')),
          _Divisor(color: colors.border),
          Expanded(child: _Columna(valor: '$activos', label: 'ACTIVOS')),
          _Divisor(color: colors.border),
          Expanded(child: _Columna(valor: '$inactivos', label: 'INACTIVOS')),
          _Divisor(color: colors.border),
          Expanded(child: _Columna(valor: '$nuevos', label: 'NUEVOS')),
        ],
      ),
    );
  }
}

class _Divisor extends StatelessWidget {
  const _Divisor({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(width: 1, height: 36, color: color);
}

class _Columna extends StatelessWidget {
  const _Columna({required this.valor, required this.label});

  final String valor;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          valor,
          style: AppTypography.sectionTitle(context).copyWith(color: colors.textPrimary, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: AppTypography.caption(context).copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Chip de filtro (§7.9) — mismo tratamiento visual que `_ToggleChip` de Gestión de Horarios,
/// duplicado localmente a propósito: cada pantalla de este código ya define sus propios widgets
/// de chip/sección privados en vez de un componente compartido (ver `gestion_horarios_screen.dart`).
class _FiltroChip extends StatelessWidget {
  const _FiltroChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: selected ? null : Border.all(color: colors.border),
        ),
        child: Text(
          label,
          style: AppTypography.caption(context).copyWith(
                color: selected ? colors.onPrimary : colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

/// Fila de paciente (§5.8bis): nombre + `StatusPill.paciente`, email, teléfono (si no es null),
/// última visita, y acciones Ver/Editar/Historial (ninguna otra — ver nota de la pantalla).
class _PacienteCard extends StatelessWidget {
  const _PacienteCard({required this.paciente});

  final _Paciente paciente;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final estado = paciente.activo ? PacienteEstado.activo : PacienteEstado.inactivo;
    final ultimaVisitaTexto = paciente.ultimaVisita != null
        ? DateFormat('d MMM yyyy', 'es').format(paciente.ultimaVisita!)
        : 'Sin visitas registradas';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        // Fondo levemente distinto para pacientes inactivos (§5.8bis: "la card completa cambia
        // de fondo (gris claro) cuando el paciente está Inactivo") — reutiliza `background`
        // (fondo de pantalla), sin introducir un color nuevo.
        color: paciente.activo ? colors.surface : colors.background,
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
                  paciente.nombre,
                  style: AppTypography.subtitle(context)
                      .copyWith(color: colors.textPrimary, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusPill.paciente(estado),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(paciente.email, style: AppTypography.caption(context)),
          if (paciente.telefono != null) ...[
            const SizedBox(height: 2),
            Text(paciente.telefono!, style: AppTypography.caption(context)),
          ],
          const SizedBox(height: 2),
          Text('Última visita: $ultimaVisitaTexto', style: AppTypography.caption(context)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _AccionPaciente(
                icon: Icons.visibility_outlined,
                label: 'Ver',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FichaPacienteScreen(pacienteId: paciente.id, pacienteNombre: paciente.nombre),
                  ),
                ),
              ),
              _AccionPaciente(
                icon: Icons.edit_outlined,
                label: 'Editar',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FichaPacienteScreen(
                      pacienteId: paciente.id,
                      pacienteNombre: paciente.nombre,
                      modoInicial: FichaPacienteModo.editar,
                    ),
                  ),
                ),
              ),
              _AccionPaciente(
                icon: Icons.history,
                label: 'Historial',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HistorialPacienteScreen(pacienteId: paciente.id, pacienteNombre: paciente.nombre),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccionPaciente extends StatelessWidget {
  const _AccionPaciente({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Expanded(
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: colors.primary),
        label: Text(
          label,
          style: AppTypography.caption(context).copyWith(color: colors.primary, fontWeight: FontWeight.w600),
        ),
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
      ),
    );
  }
}
