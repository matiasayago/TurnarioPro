import 'package:flutter/material.dart';

import '../dominio/catalogo_rubros.dart';
import '../theme/app_spacing.dart';

/// Selector de "Rubro" contra [catalogoRubros] — factoriza la lógica compartida por las 2
/// pantallas que hoy editan `negocio.rubro`: `screens/registro_negocio_screen.dart` (alta,
/// HU-00a, campo opcional) y `screens/profesional/configuracion_consultorio_screen.dart`
/// (`_vistaEditar`, modo administrador, HU-31, campo también opcional). NO se usa en `_vistaVer`
/// de esa segunda pantalla (rol profesional, solo lectura) — ese modo sigue mostrando `rubro`
/// como texto plano; nunca es editable ahí, ver el doc-comment de esa clase.
///
/// [onChanged] entrega directo el valor final a mandar al backend (`String?`, con el mismo
/// criterio "vacío es null" que `_vacioANull` ya usa cada pantalla para sus otros campos) — los
/// callers no necesitan volver a aplicar ese criterio sobre lo que reciben acá.
///
/// Lógica de arranque, a partir de [valorInicial] (el `rubro` ya cargado desde el backend, o
/// `null`/vacío en un alta nueva sin nada tipeado todavía):
/// - Coincide EXACTO (sensible a mayúsculas/tildes, a propósito: la razón de ser de este
///   catálogo es frenar inconsistencias como "Estética"/"Estetica", así que un valor viejo con
///   ese tipo de typo NUNCA se autocorrige en silencio a la opción "correcta") con una entrada de
///   [catalogoRubros]: el dropdown arranca en esa opción.
/// - Está vacío/`null`: el dropdown arranca SIN selección (con [_hintRubro] de placeholder) en
///   vez de forzar [rubroOtro] como default — el campo es opcional en las 2 pantallas que lo
///   usan, y arrancar en "Otro" con un campo de texto vacío debajo se leería como si hiciera
///   falta completar algo obligatorio.
/// - Cualquier otro valor no vacío (un valor viejo tipo "Estetica" sin tilde, o cualquier texto
///   libre cargado en un negocio antes de que existiera este catálogo): el dropdown arranca en
///   [rubroOtro] y aparece un campo de texto secundario debajo, precargado con ese valor tal cual
///   estaba — para no perderlo silenciosamente ni obligar a perder el dato ya existente.
class CampoRubro extends StatefulWidget {
  const CampoRubro({super.key, required this.valorInicial, required this.onChanged, this.enabled = true});

  final String? valorInicial;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  State<CampoRubro> createState() => _CampoRubroState();
}

const String _hintRubro = 'Seleccionar rubro...';

class _CampoRubroState extends State<CampoRubro> {
  late String? _opcion;
  late final TextEditingController _otroCtrl;

  @override
  void initState() {
    super.initState();
    final valor = widget.valorInicial?.trim() ?? '';
    if (valor.isEmpty) {
      _opcion = null;
      _otroCtrl = TextEditingController();
    } else if (catalogoRubros.contains(valor)) {
      _opcion = valor;
      _otroCtrl = TextEditingController();
    } else {
      _opcion = rubroOtro;
      _otroCtrl = TextEditingController(text: valor);
    }
  }

  @override
  void dispose() {
    _otroCtrl.dispose();
    super.dispose();
  }

  String? _vacioANull(String texto) => texto.trim().isEmpty ? null : texto.trim();

  void _emitir() => widget.onChanged(_opcion == rubroOtro ? _vacioANull(_otroCtrl.text) : _opcion);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _opcion,
          isExpanded: true,
          decoration: InputDecoration(labelText: 'Rubro', enabled: widget.enabled),
          hint: const Text(_hintRubro),
          items: [
            for (final opcion in catalogoRubros)
              DropdownMenuItem(value: opcion, child: Text(opcion, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: widget.enabled
              ? (valor) {
                  setState(() => _opcion = valor);
                  _emitir();
                }
              : null,
        ),
        // Solo cuando "Otro" está elegido (ver doc-comment de la clase) — nunca se pierde el
        // texto ya tipeado acá al ocultarse: si se vuelve a elegir "Otro" más tarde en la misma
        // sesión de edición, `_otroCtrl` sigue teniendo el mismo valor de antes.
        if (_opcion == rubroOtro) ...[
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _otroCtrl,
            enabled: widget.enabled,
            decoration: const InputDecoration(labelText: 'Especificá el rubro'),
            onChanged: (_) => _emitir(),
          ),
        ],
      ],
    );
  }
}
