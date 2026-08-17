/// Catálogo fijo de opciones para "Rubro" (columna `negocio.rubro`, `TEXT` libre — SIN `CHECK`
/// ni enum del lado del backend, y este cambio no lo agrega: sigue siendo así a propósito, ver
/// más abajo). Hasta este cambio (2026-08-17), "Rubro" se cargaba como texto libre en las dos
/// pantallas que lo editan (`screens/registro_negocio_screen.dart`, alta pre-auth, y
/// `screens/profesional/configuracion_consultorio_screen.dart` en modo administrador) y ya
/// generó datos inconsistentes en producción: confirmado contra los negocios reales de Render
/// que "Estética" y "Estetica" (sin tilde) conviven como si fueran dos rubros distintos, siendo
/// el mismo con un typo. Pedido explícito del CEO tras probar la app: reemplazar el texto libre
/// por este catálogo en ambas pantallas — ver `widgets/campo_rubro.dart` (`CampoRubro`), el
/// único widget que lo consume.
///
/// Dos cosas que este catálogo deliberadamente NO hace, para no asumir de más:
/// - No tiene ninguna relación con `negocio.es_rubro_salud` — es una columna booleana totalmente
///   independiente (no se deriva de qué opción de acá se elige) y no editable desde ninguna de
///   las dos pantallas de arriba.
/// - No se usa para filtrar ni buscar negocios en ningún lado —
///   `screens/cliente/buscar_negocios_screen.dart` solo concatena `rubro` como texto en el
///   subtítulo de cada card, junto a `ubicacion`.
///
/// La restricción es 100% de UX del lado de Mobile: el backend sigue aceptando cualquier string
/// en `rubro` sin validar contra esta lista (sin migración ni cambio de contrato), para no
/// romper negocios ya cargados con un valor que no está acá — ver [rubroOtro].
const List<String> catalogoRubros = [
  'Salud',
  'Estética',
  'Peluquería y Barbería',
  'Spa y Bienestar',
  'Gimnasio y Entrenamiento',
  'Veterinaria',
  'Legal y Contable',
  rubroOtro,
];

/// Última opción de [catalogoRubros] — ver el doc-comment de `CampoRubro`
/// (`widgets/campo_rubro.dart`) para la lógica completa de cuándo el dropdown la asume por
/// default y qué pasa con el valor existente en ese caso (nunca se pierde ni se autocorrige en
/// silencio).
const String rubroOtro = 'Otro';
