import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';

/// Configuración de Consultorio (Panel Profesional > Configuración de Consultorio, HU-31,
/// `configuracion_screen.dart`). Contrato: `GET /negocios/:id` (público, sin auth) ->
/// `{ id, nombre, rubro, ubicacion, es_rubro_salud }`. `:id` es el `negocio_id` del JWT del
/// profesional (`Sesion.negocioId`, decodificado del token en `state/sesion.dart`).
///
/// **DE SOLO LECTURA en este ciclo — a propósito, no un recorte de alcance por tiempo.** El
/// backend ya expone `PATCH /negocios/:id` (`negocios.ts`) con el mismo shape completo
/// (`nombre`, `rubro`, `ubicacion`), pero ese endpoint exige `requireAuth('administrador')`: un
/// token de rol `profesional` recibe 403 SIEMPRE, sin excepción (verificado contra la base real
/// antes de este ciclo). Y esta pantalla solo es alcanzable desde `ProfesionalShell` — es decir,
/// SIEMPRE con un JWT de rol `profesional`, nunca `administrador`. Construir un formulario
/// editable que termina en 403 en el 100% de los casos sería peor UX que no ofrecerlo.
///
/// `main.dart` (`_Router`) todavía no tiene ningún shell propio para el rol `administrador` (cae
/// a `LoginScreen` como placeholder, ver ese archivo) — cuando exista, ESA es la UI correcta para
/// agregar el formulario editable reusando `PATCH /negocios/:id` tal cual (mismo criterio de
/// "reenviar el objeto completo" que ya usa `actualizarNegocioSchema`). No hace falta ningún
/// cambio de backend en ese momento, solo la UI del lado de la app que sí tiene permiso.
class ConfiguracionConsultorioScreen extends StatefulWidget {
  const ConfiguracionConsultorioScreen({super.key});

  @override
  State<ConfiguracionConsultorioScreen> createState() => _ConfiguracionConsultorioScreenState();
}

class _ConfiguracionConsultorioScreenState extends State<ConfiguracionConsultorioScreen> {
  late Future<Map<String, dynamic>> _futureNegocio;

  @override
  void initState() {
    super.initState();
    final sesion = context.read<Sesion>();
    final negocioId = sesion.negocioId;
    _futureNegocio = negocioId == null
        ? Future.error(Exception('No se pudo determinar tu consultorio (falta negocio_id en la sesión).'))
        : sesion.api.getMap('/negocios/$negocioId');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: const AppHeader(
        variant: AppHeaderVariant.surface,
        emoji: '🏬',
        title: 'Configuración de Consultorio',
        showBackButton: true,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _futureNegocio,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Center(
                child: Text('No se pudo cargar tu consultorio: ${snapshot.error}', style: AppTypography.body(context)),
              ),
            );
          }

          final negocio = snapshot.data!;
          final rubro = negocio['rubro'] as String?;
          final ubicacion = negocio['ubicacion'] as String?;
          final esRubroSalud = negocio['es_rubro_salud'] == true;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionCard(
                  context,
                  title: 'Datos del consultorio',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRow(context, 'Nombre', negocio['nombre'] as String),
                      _infoRow(context, 'Rubro', (rubro == null || rubro.isEmpty) ? 'Sin especificar' : rubro),
                      _infoRow(
                        context,
                        'Ubicación',
                        (ubicacion == null || ubicacion.isEmpty) ? 'Sin especificar' : ubicacion,
                      ),
                      _infoRow(context, 'Rubro de salud', esRubroSalud ? 'Sí' : 'No', esUltimo: true),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.base),
                  decoration: BoxDecoration(
                    color: colors.neutral.background,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 18, color: colors.neutral.base),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Estos datos son de solo lectura. Los administra el dueño del negocio; todavía no hay '
                          'una sección de Administrador en esta app para editarlos.',
                          style: AppTypography.caption(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
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
