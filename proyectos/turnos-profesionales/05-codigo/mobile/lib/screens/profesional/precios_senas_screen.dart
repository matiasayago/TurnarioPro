import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';

/// Precios y Señas (Configuración de Pagos, HU-04b/D2/RN10). Alcanzable desde DOS ítems del menú
/// de `configuracion_screen.dart` que hoy apuntan al mismo concepto real: "Configuración de
/// Pagos" (Panel Profesional) y "Pagos y Señas" (sección propia) — la seña ya se configura por
/// asociación profesional↔servicio (HU-04b); no hay backend para los otros sub-ítems que muestra
/// `mapa-pantallas.md` §5.11bis bajo "Pagos y Señas" (el toggle "Reservas online con seña" a
/// nivel negocio, "Historial de Señas"), así que quedan fuera de esta ronda. También alcanzable
/// (2026-08-20) desde "Editar Perfil" > "Servicios que brindo", botón "Editar seña" de un
/// servicio ya asociado (ver `editar_perfil_screen.dart`) — mismo destino, sin duplicar la lógica
/// de edición en 2 pantallas.
///
/// Contrato: `GET /profesionales/:id/servicios` -> array de `{ servicio_id, nombre,
/// duracion_min, precio_referencia, negocio_id, negocio_nombre, requiere_sena, monto_sena }` —
/// TODOS los servicios que el profesional ya asoció a su agenda (alta vía la sección
/// "Configurar Disponibilidad", no esta pantalla). `PATCH /profesionales/:id/servicios/:servicioId`,
/// body `{ requiere_sena: boolean, monto_sena: number | null }` -> `{ servicio_id, requiere_sena,
/// monto_sena }`.
///
/// **Guardado por fila, no un botón general único**: cada servicio es una edición independiente
/// contra un endpoint que ya opera por `:servicioId` puntual (no existe un PATCH en lote) — un
/// botón general obligaría a decidir qué hacer si el guardado de un servicio falla y el de otro
/// no (¿se revierte todo? ¿queda a mitad de camino?). Guardar fila por fila evita esa ambigüedad:
/// cada tarjeta es su propia unidad de guardado, con su propio estado de carga/error, igual que
/// cada fila de una lista de configuración independiente.
class PreciosSenasScreen extends StatefulWidget {
  const PreciosSenasScreen({super.key});

  @override
  State<PreciosSenasScreen> createState() => _PreciosSenasScreenState();
}

class _PreciosSenasScreenState extends State<PreciosSenasScreen> {
  late Future<List<_ServicioPago>> _futureServicios;

  @override
  void initState() {
    super.initState();
    _futureServicios = _cargar();
  }

  Future<List<_ServicioPago>> _cargar() async {
    final sesion = context.read<Sesion>();
    final raw = await sesion.api.getList('/profesionales/${sesion.profesionalId}/servicios');
    return raw.map((e) => _ServicioPago.fromApi(e as Map<String, dynamic>)).toList();
  }

  Future<void> _refrescar() async {
    final next = _cargar();
    setState(() => _futureServicios = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(
        variant: AppHeaderVariant.surface,
        emoji: '💳',
        title: 'Precios y Señas',
        showBackButton: true,
      ),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<List<_ServicioPago>>(
          future: _futureServicios,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ListView(
                children: const [SizedBox(height: 160), Center(child: CircularProgressIndicator())],
              );
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Center(
                    child: Text(
                      'No se pudieron cargar tus servicios: ${snapshot.error}',
                      style: AppTypography.body(context),
                    ),
                  ),
                ],
              );
            }

            final servicios = snapshot.data ?? [];
            if (servicios.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Center(
                    child: Text(
                      'Todavía no tenés servicios asociados a tu agenda. Cuando asocies uno, vas a poder '
                      'configurar acá si requiere seña para reservar.',
                      textAlign: TextAlign.center,
                      style: AppTypography.body(context),
                    ),
                  ),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                Text(
                  'Configurá, servicio por servicio, si requiere seña para reservar y el monto.',
                  style: AppTypography.caption(context),
                ),
                const SizedBox(height: AppSpacing.base),
                for (final servicio in servicios) _ServicioSenaCard(key: ValueKey(servicio.servicioId), servicio: servicio),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Formatea un monto sin decimales sobrantes (`5000` en vez de `5000.0`) — `precio_referencia`/
/// `monto_sena` llegan como `num` (NUMERIC de Postgres, parseado a `double` por `db.ts` del
/// backend, ver `pgTypes.setTypeParser(1700, parseFloat)`), pero la mayoría de los valores reales
/// de este dominio no tienen centavos.
String _formatMonto(num valor) {
  if (valor == valor.roundToDouble()) return valor.toStringAsFixed(0);
  return valor.toStringAsFixed(2);
}

class _ServicioPago {
  const _ServicioPago({
    required this.servicioId,
    required this.nombre,
    required this.duracionMin,
    required this.precioReferencia,
    required this.negocioNombre,
    required this.requiereSena,
    required this.montoSena,
  });

  final String servicioId;
  final String nombre;
  final int duracionMin;
  final num? precioReferencia;
  final String negocioNombre;
  final bool requiereSena;
  final num? montoSena;

  factory _ServicioPago.fromApi(Map<String, dynamic> json) => _ServicioPago(
        servicioId: json['servicio_id'] as String,
        nombre: json['nombre'] as String,
        duracionMin: json['duracion_min'] as int,
        precioReferencia: json['precio_referencia'] as num?,
        negocioNombre: json['negocio_nombre'] as String,
        requiereSena: json['requiere_sena'] as bool? ?? false,
        montoSena: json['monto_sena'] as num?,
      );
}

class _ServicioSenaCard extends StatefulWidget {
  const _ServicioSenaCard({super.key, required this.servicio});

  final _ServicioPago servicio;

  @override
  State<_ServicioSenaCard> createState() => _ServicioSenaCardState();
}

class _ServicioSenaCardState extends State<_ServicioSenaCard> {
  late bool _requiereSena;
  late final TextEditingController _montoCtrl;

  bool _guardando = false;
  String? _mensaje;
  bool _mensajeEsError = false;

  @override
  void initState() {
    super.initState();
    _requiereSena = widget.servicio.requiereSena;
    _montoCtrl = TextEditingController(
      text: widget.servicio.montoSena != null ? _formatMonto(widget.servicio.montoSena!) : '',
    );
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    double? monto;
    if (_requiereSena) {
      monto = double.tryParse(_montoCtrl.text.trim().replaceAll(',', '.'));
      if (monto == null || monto <= 0) {
        setState(() {
          _mensaje = 'Ingresá un monto válido mayor a 0.';
          _mensajeEsError = true;
        });
        return;
      }
    }
    setState(() {
      _guardando = true;
      _mensaje = null;
    });
    final sesion = context.read<Sesion>();
    try {
      await sesion.api.patch('/profesionales/${sesion.profesionalId}/servicios/${widget.servicio.servicioId}', {
        'requiere_sena': _requiereSena,
        'monto_sena': monto,
      });
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _mensaje = 'Guardado.';
        _mensajeEsError = false;
      });
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
    final colors = AppColors.of(context);
    final servicio = widget.servicio;
    final precio = servicio.precioReferencia != null
        ? '\$${_formatMonto(servicio.precioReferencia!)}'
        : 'sin precio de referencia';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppRadius.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(servicio.nombre, style: AppTypography.sectionTitle(context)),
          const SizedBox(height: 2),
          Text(
            '${servicio.negocioNombre} · ${servicio.duracionMin} min · $precio',
            style: AppTypography.caption(context),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Requiere seña para reservar', style: AppTypography.body(context)),
            value: _requiereSena,
            onChanged: _guardando ? null : (v) => setState(() => _requiereSena = v),
          ),
          if (_requiereSena) ...[
            TextField(
              controller: _montoCtrl,
              enabled: !_guardando,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto de la seña', prefixText: '\$ '),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (_mensaje != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _mensaje!,
              style: AppTypography.caption(context).copyWith(color: _mensajeEsError ? colors.danger.base : colors.success.base),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: PrimaryButton(
              label: 'Guardar',
              radiusVariant: AppButtonRadius.card,
              expand: false,
              loading: _guardando,
              onPressed: _guardando ? null : _guardar,
            ),
          ),
        ],
      ),
    );
  }
}
