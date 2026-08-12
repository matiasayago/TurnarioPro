import { Router } from 'express';
import { z } from 'zod';
import { pool, nowIso, withTransaction } from '../db';
import { requireAuth, AuthedRequest } from '../auth';
import { asyncHandler } from '../middleware/asyncHandler';
import { visibilidadPerfilSchema, respuestaValidacionFallida } from '../dominio/validacion';

// Configuración > Cuenta del lado Profesional (mapa-pantallas.md §5.11/§5.11bis, menú "Cuenta":
// "Editar Perfil" + "Privacidad y Seguridad" — acá se modela únicamente el bloque "Privacidad"
// de esa segunda pantalla, ver el comentario junto a /privacidad más abajo) — pero, a diferencia
// de otras pantallas de esta ronda, NO es exclusiva del rol profesional: tanto "Editar Perfil"
// como "Privacidad y Seguridad" (HU-32) son transversales a cualquier rol autenticado
// (cliente/profesional/administrador), así que este router no exige ningún rol puntual.
//
// Router NUEVO — no existía ningún endpoint genérico de "mi perfil"/"mis preferencias" antes de
// este ciclo. Cada router existente está scopeado a una entidad de negocio con dueño explícito
// (negocio/profesional/turno) — `clientes.ts`, pese al nombre, opera sobre `usuario`+`turno`
// filtrado por el ROL cliente en una relación con un profesional puntual, no sobre "un usuario
// cualquiera editando sus propios datos". Decisiones de nombre/ubicación (documentadas acá según
// lo pedido, no hay un criterio previo del proyecto que las fije):
//   - Archivo nuevo `src/routes/usuario.ts`, montado en `/usuario` (ver src/app.ts) — NO
//     `/usuarios` en plural: el resto de los routers de este backend SÍ son plurales
//     (negocios/profesionales/turnos/clientes) porque exponen colecciones de recursos ajenos al
//     caller (ej. "todos los negocios", "los turnos de tal profesional"). Acá, en cambio, cada
//     ruta opera EXCLUSIVAMENTE sobre la propia fila del usuario autenticado — no existe
//     `GET/PATCH /usuario/:id` de un tercero, ni ningún listado — así que el plural sugeriría una
//     API de colección que esto deliberadamente no es.
//   - Prefijo `usuario` (no `cuenta`, pese a que mapa-pantallas.md agrupa "Editar Perfil" +
//     "Privacidad y Seguridad" bajo un menú de UI llamado "Cuenta"): se prioriza que el prefijo
//     de ruta identifique sin ambigüedad la tabla que toca — mismo criterio que
//     negocios/profesionales/turnos, cada uno 1:1 con su tabla principal — por sobre replicar la
//     agrupación de navegación de UI, que es responsabilidad de Mobile y puede reagruparse sin
//     que el backend tenga que seguirle el nombre.
//   - Dos sub-recursos hermanos bajo este mismo router, uno por tabla: `/usuario/perfil` (tabla
//     `usuario`, SIN RLS) y `/usuario/privacidad` (tabla `usuario_preferencias`, satélite 1:1 de
//     `usuario` — mismo patrón que `profesional`, ver 001_init.sql —, CON RLS FORCE). El bloque
//     "Seguridad de la cuenta" que el wireframe original mostraba junto a "Privacidad" NO se
//     modela acá: UX/UI confirmó contra una captura real que no existe en la app de referencia y
//     no tiene HU propia (ver 001_init.sql, bloque "Preferencias de privacidad de usuario") — así
//     que este router no reserva ningún sub-recurso para eso.
export const usuarioRouter = Router();

// Body de PATCH /usuario/perfil. `email` NO está en este schema a propósito — ver el comentario
// en el handler de abajo. Ambos campos viajan siempre (no `.optional()`): mismo criterio de
// "reenviar el formulario completo" que `fichaPacienteSchema`/`configuracionProfesionalSchema`
// en profesionales.ts — Mobile ya tiene el valor actual desde el GET de abajo. `telefono`
// nullable (columna nullable en `usuario`; el usuario puede vaciarlo).
const perfilSchema = z.object({
  nombre: z.string().min(1, 'nombre es requerido'),
  telefono: z.string().nullable(),
});

// Body de PATCH /usuario/privacidad — los 3 controles de HU-32/mapa-pantallas.md §5.13, todos
// requeridos (mismo criterio de reenvío completo que arriba: el footer real tiene un solo botón
// "Guardar" para el bloque entero, no autoguardado campo por campo).
const privacidadSchema = z.object({
  visibilidad_perfil: visibilidadPerfilSchema,
  mostrar_estado_en_linea: z.boolean(),
  compartir_datos_uso: z.boolean(),
});

// Defaults de "fábrica" — MISMOS 3 valores que el DEFAULT de cada columna en
// usuario_preferencias (001_init.sql / 003_privacidad_usuario.sql): 'publico' / true / true.
// Recomendación de DBA en ese mismo archivo: "mientras no exista fila para un usuario_id dado,
// la aplicación puede devolver los 3 DEFAULT... sin tocar la base (0 filas = todavía en default
// de fábrica, nunca personalizó nada)" — ver GET /privacidad más abajo.
const DEFAULTS_PRIVACIDAD = {
  visibilidad_perfil: 'publico' as const,
  mostrar_estado_en_linea: true,
  compartir_datos_uso: true,
};

// ============================================================================
// GET/PATCH /usuario/perfil — Editar Perfil (mapa-pantallas.md §5.11bis, "Cuenta > Editar
// Perfil"). Cualquier rol autenticado, siempre sobre uno mismo (`req.auth.sub`, nunca un `:id`
// de otro usuario).
// ============================================================================

// Contrato: GET /usuario/perfil -> 200 { id, nombre, email, telefono, rol } | 401 sin token
// válido | 404 (defensivo, ver más abajo).
usuarioRouter.get(
  '/perfil',
  requireAuth(),
  asyncHandler(async (req: AuthedRequest, res) => {
    // `usuario` NO tiene Row Level Security habilitada (ver el comentario junto a
    // `CREATE TABLE usuario` en migrations/001_init.sql — gap ya documentado, preexistente, no
    // introducido acá) — `pool.query` directo, sin `withTransaction`, mismo patrón que ya usan
    // las lecturas de `usuario` en src/routes/auth.ts (ej. `SELECT * FROM usuario WHERE email =
    // $1` en POST /auth/login).
    const result = await pool.query('SELECT id, nombre, email, telefono, rol FROM usuario WHERE id = $1', [
      req.auth!.sub,
    ]);
    const usuario = result.rows[0];
    // Defensivo — no debería poder pasar con un JWT recién emitido (el claim `sub` siempre sale
    // de un `usuario.id` real), pero el token sigue siendo válido hasta 2h (ver signToken en
    // src/auth.ts) y este proyecto todavía no tiene ningún flujo de baja de cuenta que pudiera
    // invalidar tokens ya emitidos — se prefiere un 404 explícito a un 500 si alguna vez pasa.
    if (!usuario) return res.status(404).json({ error: 'Usuario no encontrado' });
    res.json(usuario);
  })
);

// Contrato: PATCH /usuario/perfil, body { nombre: string, telefono: string | null } -> 200
// { id, nombre, email, telefono, rol } | 400 datos inválidos | 401 sin token válido | 404
// (defensivo, ver GET de arriba).
usuarioRouter.patch(
  '/perfil',
  requireAuth(),
  asyncHandler(async (req: AuthedRequest, res) => {
    const bodyParsed = perfilSchema.safeParse(req.body);
    if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
    const { nombre, telefono } = bodyParsed.data;

    // `email` es de SOLO LECTURA en este ciclo — es el identificador único de login
    // (`usuario.email UNIQUE`) y cambiarlo tiene implicancias fuera de este alcance: colisión de
    // unicidad a validar, y para cuentas vinculadas a Google (HU-35, `usuario.google_id`)
    // quedaría desincronizado del email real de esa cuenta. El schema de arriba ni siquiera
    // declara el campo `email`: si el body lo trae igual, zod lo descarta en silencio
    // (comportamiento default de `.object()` — ningún schema de este proyecto usa `.strict()`)
    // en vez de responder 400 — mismo resultado práctico ("no se puede cambiar acá"), consistente
    // con el resto de la API.
    //
    // `usuario` no tiene RLS — UPDATE directo vía `pool.query`, sin `withTransaction`, mismo
    // patrón que el `UPDATE usuario SET google_id = ...` de POST /auth/login
    // (src/routes/auth.ts): una sola sentencia sobre una tabla sin RLS no necesita ni contexto de
    // sesión ni la atomicidad de una transacción multi-sentencia.
    const result = await pool.query(
      `UPDATE usuario SET nombre = $1, telefono = $2, modificado_en = $3
       WHERE id = $4
       RETURNING id, nombre, email, telefono, rol`,
      [nombre, telefono, nowIso(), req.auth!.sub]
    );
    const usuario = result.rows[0];
    if (!usuario) return res.status(404).json({ error: 'Usuario no encontrado' });
    res.json(usuario);
  })
);

// ============================================================================
// GET/PATCH /usuario/privacidad — bloque "Privacidad" de HU-32 (mapa-pantallas.md §5.13/§5.13bis,
// "Cuenta > Privacidad y Seguridad"). Cualquier rol autenticado, siempre sobre uno mismo. El
// bloque "Seguridad de la cuenta" del mismo wireframe NO se modela (ver nota junto al `export
// const usuarioRouter` de arriba).
// ============================================================================

// Contrato: GET /usuario/privacidad -> 200 { visibilidad_perfil, mostrar_estado_en_linea,
// compartir_datos_uso } (defaults de fábrica si la cuenta nunca guardó preferencias — NUNCA
// 404) | 401 sin token válido.
usuarioRouter.get(
  '/privacidad',
  requireAuth(),
  asyncHandler(async (req: AuthedRequest, res) => {
    // `usuario_preferencias` SÍ tiene RLS FORCE (policy `usuario_preferencias_acceso_propio`,
    // `usuario_id = app.usuario_id` — ver 001_init.sql / 003_privacidad_usuario.sql) — a
    // diferencia de GET /perfil de arriba, esto NO puede resolverse con `pool.query` directo: sin
    // `app.usuario_id` seteado, la policy devuelve 0 filas SIEMPRE, incluso para una cuenta que
    // YA personalizó su privacidad — mentiría "está en default" en vez de reflejar lo guardado.
    // `withTransaction` con contexto es obligatorio acá, inclusive para esta lectura (no soLo
    // para el PATCH de abajo).
    const fila = await withTransaction(
      async (client) => {
        const result = await client.query(
          `SELECT visibilidad_perfil, mostrar_estado_en_linea, compartir_datos_uso
           FROM usuario_preferencias WHERE usuario_id = $1`,
          [req.auth!.sub]
        );
        return result.rows[0] as
          | { visibilidad_perfil: string; mostrar_estado_en_linea: boolean; compartir_datos_uso: boolean }
          | undefined;
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );
    // Sin fila todavía (cuenta creada antes de este ciclo — DBA no puso alta automática — o que
    // nunca guardó nada acá) -> los 3 defaults de fábrica, NUNCA un 404: HU-32 es transversal a
    // cualquier cuenta existente, no una funcionalidad opt-in que requiera un paso de alta previo.
    res.json(fila ?? DEFAULTS_PRIVACIDAD);
  })
);

// Contrato: PATCH /usuario/privacidad, body { visibilidad_perfil: 'publico'|'solo_contactos'|
// 'privado', mostrar_estado_en_linea: boolean, compartir_datos_uso: boolean } -> 200
// { visibilidad_perfil, mostrar_estado_en_linea, compartir_datos_uso } | 400 datos inválidos |
// 401 sin token válido.
usuarioRouter.patch(
  '/privacidad',
  requireAuth(),
  asyncHandler(async (req: AuthedRequest, res) => {
    const bodyParsed = privacidadSchema.safeParse(req.body);
    if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
    const { visibilidad_perfil, mostrar_estado_en_linea, compartir_datos_uso } = bodyParsed.data;

    // Upsert (`INSERT ... ON CONFLICT ... DO UPDATE`) — mismo patrón que PATCH
    // /profesionales/:id/pacientes/:pacienteId (src/routes/profesionales.ts, referencia directa
    // pedida para este endpoint): la fila puede no existir todavía (ver GET de arriba), así que
    // el primer "Guardar" la crea y cualquier guardado siguiente la actualiza, con una sola
    // sentencia. Más simple que ese otro caso: acá el UNIQUE es directo sobre `usuario_id` (sin
    // negocio/profesional de por medio que resolver condicionalmente) — un usuario tiene como
    // mucho una sola fila de preferencias, sin ambigüedad posible.
    const preferencias = await withTransaction(
      async (client) => {
        const ts = nowIso();
        const result = await client.query(
          `INSERT INTO usuario_preferencias
             (usuario_id, visibilidad_perfil, mostrar_estado_en_linea, compartir_datos_uso, creado_en)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (usuario_id) DO UPDATE SET
             visibilidad_perfil = excluded.visibilidad_perfil,
             mostrar_estado_en_linea = excluded.mostrar_estado_en_linea,
             compartir_datos_uso = excluded.compartir_datos_uso,
             modificado_en = $6
           RETURNING visibilidad_perfil, mostrar_estado_en_linea, compartir_datos_uso`,
          [req.auth!.sub, visibilidad_perfil, mostrar_estado_en_linea, compartir_datos_uso, ts, ts]
        );
        return result.rows[0];
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );
    res.json(preferencias);
  })
);
