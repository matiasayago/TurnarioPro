import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';

/// Configuración de Notificaciones (granular) — HU-26 (`mapa-pantallas.md` §5.14). Se llega acá
/// desde dos lugares: el ítem "Notificaciones" de `configuracion_screen.dart` (sección Cuenta) y
/// el ícono ⚙ del header de `notificaciones_screen.dart` (§5.15) — mismo destino en ambos casos,
/// sin duplicar esta pantalla.
///
/// Contrato: `GET /notificaciones/configuracion` -> los 7 booleanos de abajo (defaults de fábrica
/// si la cuenta nunca guardó nada, nunca 404); `PATCH /notificaciones/configuracion`, mismo body
/// completo (los 7 campos siempre, el backend no acepta parches parciales) -> mismo shape. Mismo
/// patrón de pantalla que `PrivacidadScreen` (`feature/configuracion-profesional`, todavía sin
/// mergear a esta rama): `FutureBuilder<void>` que carga a variables locales, un solo botón
/// "Guardar" en el footer que reenvía el formulario entero — el wireframe real (§5.14bis) muestra
/// 3 botones (Cancelar/Guardar/Restablecer), pero `PrivacidadScreen` ya estableció el criterio de
/// simplificar a uno solo para este ciclo de pantallas de Configuración, y se mantiene acá por
/// consistencia.
///
/// Secciones, en el orden del wireframe: "Canal" (Push/Email/WhatsApp), "Tipo de aviso" (Citas y
/// recordatorios / Promociones y Ofertas — "Mensajes" y "Reseñas y Calificaciones" quedan
/// OCULTOS, decisión ya tomada por UX/UI porque esas funciones no existen en el backlog) y
/// "Sonido y vibración" (Sonido/Vibración).
///
/// **WhatsApp se trata como una preferencia más, sin aviso de "no disponible".** HU-24
/// (integración real de WhatsApp Business) está bloqueada para desarrollo, pero
/// `notif_canal_whatsapp` es una columna real que el backend persiste igual que las otras 6 — el
/// usuario puede activarla/desactivarla hoy mismo, y ese valor queda guardado para cuando HU-24
/// se desbloquee. Deshabilitar el switch o agregarle una leyenda de "próximamente" sería inventar
/// un estado que el backend no tiene.
class ConfiguracionNotificacionesScreen extends StatefulWidget {
  const ConfiguracionNotificacionesScreen({super.key});

  @override
  State<ConfiguracionNotificacionesScreen> createState() => _ConfiguracionNotificacionesScreenState();
}

class _ConfiguracionNotificacionesScreenState extends State<ConfiguracionNotificacionesScreen> {
  late Future<void> _futureCarga;

  // Mismos defaults de fábrica que `DEFAULTS_CONFIGURACION_NOTIFICACIONES` en
  // `routes/notificaciones.ts` — solo importan como valor inicial antes de que resuelva
  // `_futureCarga` (el formulario no se muestra hasta entonces), pero se mantienen alineados para
  // no mostrar nunca un estado inconsistente con lo que el backend considera "de fábrica".
  bool _canalPush = true;
  bool _canalEmail = true;
  bool _canalWhatsapp = true;
  bool _citasRecordatorios = true;
  bool _promociones = false;
  bool _sonido = true;
  bool _vibracion = true;

  bool _guardando = false;
  String? _mensaje;
  bool _mensajeEsError = false;

  @override
  void initState() {
    super.initState();
    _futureCarga = _cargar();
  }

  Future<void> _cargar() async {
    final sesion = context.read<Sesion>();
    final data = await sesion.api.getMap('/notificaciones/configuracion');
    _aplicarDatos(data);
  }

  void _aplicarDatos(Map<String, dynamic> data) {
    _canalPush = data['notif_canal_push'] as bool;
    _canalEmail = data['notif_canal_email'] as bool;
    _canalWhatsapp = data['notif_canal_whatsapp'] as bool;
    _citasRecordatorios = data['notif_citas_recordatorios'] as bool;
    _promociones = data['notif_promociones'] as bool;
    _sonido = data['notif_sonido'] as bool;
    _vibracion = data['notif_vibracion'] as bool;
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _mensaje = null;
    });
    final sesion = context.read<Sesion>();
    try {
      final data = await sesion.api.patch('/notificaciones/configuracion', {
        'notif_canal_push': _canalPush,
        'notif_canal_email': _canalEmail,
        'notif_canal_whatsapp': _canalWhatsapp,
        'notif_citas_recordatorios': _citasRecordatorios,
        'notif_promociones': _promociones,
        'notif_sonido': _sonido,
        'notif_vibracion': _vibracion,
      });
      if (!mounted) return;
      setState(() {
        _aplicarDatos(data);
        _guardando = false;
        _mensaje = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preferencias guardadas.')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _mensaje = 'No se pudo guardar: $e';
        _mensajeEsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _futureCarga,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            appBar: AppHeader(
              variant: AppHeaderVariant.surface,
              emoji: '⚙️',
              title: 'Configuración de Notificaciones',
              showBackButton: true,
            ),
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: const AppHeader(
              variant: AppHeaderVariant.surface,
              emoji: '⚙️',
              title: 'Configuración de Notificaciones',
              showBackButton: true,
            ),
            body: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Center(
                child: Text(
                  'No se pudo cargar tu configuración: ${snapshot.error}',
                  style: AppTypography.body(context),
                ),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: const AppHeader(
            variant: AppHeaderVariant.surface,
            emoji: '⚙️',
            title: 'Configuración de Notificaciones',
            showBackButton: true,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionCard(
                  context,
                  title: 'Canal',
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Push', style: AppTypography.body(context)),
                        value: _canalPush,
                        onChanged: (v) => setState(() => _canalPush = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Email', style: AppTypography.body(context)),
                        value: _canalEmail,
                        onChanged: (v) => setState(() => _canalEmail = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('WhatsApp', style: AppTypography.body(context)),
                        value: _canalWhatsapp,
                        onChanged: (v) => setState(() => _canalWhatsapp = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _sectionCard(
                  context,
                  title: 'Tipo de aviso',
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Citas y recordatorios', style: AppTypography.body(context)),
                        subtitle: Text(
                          'Confirmación, recordatorio, cancelación o reprogramación de turnos, y nuevas reservas.',
                          style: AppTypography.caption(context),
                        ),
                        value: _citasRecordatorios,
                        onChanged: (v) => setState(() => _citasRecordatorios = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Promociones y Ofertas', style: AppTypography.body(context)),
                        value: _promociones,
                        onChanged: (v) => setState(() => _promociones = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _sectionCard(
                  context,
                  title: 'Sonido y vibración',
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Sonido', style: AppTypography.body(context)),
                        value: _sonido,
                        onChanged: (v) => setState(() => _sonido = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Vibración', style: AppTypography.body(context)),
                        value: _vibracion,
                        onChanged: (v) => setState(() => _vibracion = v),
                      ),
                    ],
                  ),
                ),
                if (_mensaje != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _FeedbackBanner(mensaje: _mensaje!, esError: _mensajeEsError),
                ],
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
          bottomNavigationBar: _footer(context),
        );
      },
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

  Widget _footer(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.surface,
      elevation: 8,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: PrimaryButton(
            label: 'Guardar',
            radiusVariant: AppButtonRadius.card,
            loading: _guardando,
            onPressed: _guardando ? null : _guardar,
          ),
        ),
      ),
    );
  }
}

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.mensaje, required this.esError});

  final String mensaje;
  final bool esError;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final estado = esError ? colors.danger : colors.success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(color: estado.background, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Text(mensaje, style: AppTypography.body(context).copyWith(color: estado.base)),
    );
  }
}
