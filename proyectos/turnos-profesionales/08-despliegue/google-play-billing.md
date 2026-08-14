# Suscripción "Turnario Pro" (HU-29/E11) — plan de credenciales de Google Play Billing

**Rol:** DevOps
**Fase:** 3 — Diseño técnico / prerrequisito externo. A diferencia de `./google-oauth.md` (que
corrió en paralelo a Backend ya construyendo el endpoint real de HU-35), acá **todavía no existe
ningún código de HU-29** — ni columnas en el modelo de datos, ni endpoint de Backend, ni pantalla
de Mobile (confirmado por grep sobre `../03-arquitectura/modelo-datos.md` y
`../05-codigo/backend/src/`: cero referencias a suscripción/plan/billing). Este documento es el
primer paso de todos, no uno más entre varios en paralelo — ver §1.
**Entradas:** confirmación del CEO de avanzar con HU-29 (este ciclo); `../02-backlog/backlog.md`
(HU-29/E11, precio y plataforma ya decididos por el CEO — no se re-derivan acá); `./google-oauth.md`
(formato/nivel de detalle de referencia, y un dato que este documento retoma: el proyecto de
Google Cloud "Turnos Profesionales" ya existe, ver §6); `../05-codigo/mobile/README.md` ("Gap
conocido": no existe `android/`) y `../05-codigo/mobile/flutter_launcher_icons.yaml` (branding ya
preparado, a la espera de esa carpeta); `../03-arquitectura/plan-produccion.md` §7/§8 (costos y
secuencia de cuentas de tienda, ya documentados por CTO IA antes de este ciclo).
**Salidas:** únicamente este documento y una entrada nueva en
`../../../memory/proyectos/turnos-profesionales/decisiones.md`. **Cero archivos de código
tocados** — ni `.env.example`, ni `render.yaml`, ni `backlog.md`, ni nada de `05-codigo/` (a
diferencia del ciclo de `google-oauth.md`, que sí actualizó `.env.example`/`render.yaml` porque
ahí ya existía un endpoint real esperando esa variable). Ver §0 para el porqué de esa diferencia,
y §7 para qué queda planteado (no aplicado) para cuando corresponda.
**No incluye ninguna credencial, cuenta ni pago real** — ver §0.

## 0. Qué resuelve este documento y qué NO

Resuelve, en un solo lugar, la secuencia completa de lo que hace falta para que Google Play
Billing funcione de verdad (no simulado) en este proyecto: qué tiene que hacer el CEO (cuenta,
pago, decisiones de negocio) y qué puede hacer un agente de IA una vez que el CEO dé el visto
bueno (generar la plataforma Android, la keystore de firma, y — más adelante — el código de
integración de Backend/Mobile).

**No crea ninguna cuenta real, no paga nada, no genera ningún producto de suscripción real en
Play Console, no genera ninguna keystore real, y no toca ningún archivo de `05-codigo/`.** Igual
que con las cuentas de Render/Google Cloud/Google Play Developer/Apple Developer ya documentadas
en `../03-arquitectura/plan-produccion.md` §8 y en `./google-oauth.md` §0: ningún agente de IA
puede crear una cuenta de Google Play Developer ni ingresar los datos de pago de los USD 25 —
hace falta al CEO, con su propia identidad y su propia tarjeta. Lo que sigue es el instructivo
para que lo ejecute cuando tenga tiempo, más el trabajo técnico que sí puede delegar en un agente
una vez que dé el ok explícito (§1).

**Por qué este ciclo NO toca `.env.example`/`render.yaml`/`backlog.md` (a diferencia del
precedente de `./google-oauth.md`):** cuando DevOps armó el plan de credenciales OAuth, Backend ya
estaba construyendo el endpoint real de HU-35 en paralelo, en su propia rama — declarar
`GOOGLE_CLIENT_ID` en esos archivos tenía sentido inmediato porque algo del lado del código ya
esperaba esa variable (con un gateo a 503 mientras no existiera). Acá no hay ningún endpoint ni
ninguna pantalla esperando nada todavía — declarar variables ahora sería documentación sin nada
que la consuma, y el nombre "definitivo" de alguna de ellas depende de decisiones (`applicationId`,
IDs de producto) que este mismo documento dejá planteadas pero **pendientes de confirmación del
CEO** (§3.2, §5). La lista concreta de variables queda preparada en §7, para aplicarse en un
próximo ciclo de DevOps recién cuando Backend arranque la implementación real — no antes.

**Tampoco es asesoría legal ni impositiva.** Cobrar una suscripción con tarjetas internacionales
desde Argentina puede tener implicancias impositivas (IVA/Ingresos Brutos, retenciones sobre pagos
del exterior) que este documento no evalúa — mismo criterio que ya aplicó CTO IA en
`../03-arquitectura/plan-produccion.md` §9 con la Ley 25.326: es una señal para que el CEO consulte
a su contador/abogado si corresponde, no algo que DevOps deba o pueda resolver.

## 1. Vista rápida — la secuencia completa y quién hace cada paso

No todo se puede paralelizar como en el ciclo de OAuth: acá casi todo depende de un paso anterior
de la misma cadena. Orden real (no solo una lista):

| # | Paso | Seguido en | Quién lo ejecuta |
|---|---|---|---|
| 1 | Crear la cuenta de Google Play Developer y pagar los USD 25 | §2 | **CEO** (dinero real, identidad real) |
| 2 | Generar `android/` de forma permanente en el proyecto Flutter | §3.1 | Agente (Mobile/DevOps), con visto bueno del CEO |
| 3 | Confirmar el `applicationId` definitivo | §3.2 | **CEO** decide (DevOps propone abajo) |
| 4 | Generar la keystore de firma (upload key) | §3.3 | Agente (Mobile/DevOps), técnico — el CEO custodia el resultado |
| 5 | Crear la app en Play Console y subir un build firmado a Internal testing | §4 | Mixto: CEO (alta de la app, cuestionarios) + agente (build) |
| 6 | Completar "Monetización" (cuenta de pagos de Google) | §4 | **CEO** (datos bancarios/fiscales) |
| 7 | Crear el producto de suscripción con sus 2 planes (mensual/anual) | §5 | **CEO** (en Play Console; DevOps propone los IDs) |
| 8 | Crear la cuenta de servicio (Service Account) para verificación server-side | §6 | **CEO** (con guía paso a paso) |
| 9 | Backend implementa la verificación real con esa cuenta de servicio | §7 | Backend |
| 10 | Mobile implementa la compra real (Play Billing Library) | — | Mobile |

Los pasos 1→4 son estrictamente secuenciales entre sí (no se puede firmar sin `android/`, no
conviene generar `android/` sin haber decidido el paquete). Los pasos 5→8 dependen todos de que 1→4
ya existan. Backend y Mobile (9-10) pueden **diseñar** su parte ya (pantallas, mocks, el contrato
del endpoint de verificación) sin esperar nada de esto — mismo patrón que ya usa este proyecto para
Mercado Pago (`MockPagoProvider` en `../05-codigo/backend/src/integraciones/pagos.ts`) — pero no
pueden probar una compra real hasta que exista al menos el paso 7.

## 1bis. Actualización (2026-08-14, mismo día — Director General IA, tras revisar con el CEO)

El CEO compartió una captura real de su Google Play Console. Dos ítems de este documento que
estaban marcados "Pendiente" ya están resueltos — **no ejecutar los pasos 1 y 3.2 de abajo como si
faltaran, están hechos:**

- **Paso 1 (cuenta de Google Play Developer) — YA EXISTE.** Cuenta Personal, titular "Matias
  Sayago", ID de cuenta visible en la consola. El pago de USD 25 y la decisión Personal/Organización
  (§2, punto 3) ya están resueltos — no hace falta que el CEO los repita.
- **Paso 3.2 (`applicationId`) — YA DECIDIDO, y no es `com.turnariopro.app` como una recomendación
  nueva: es un valor que YA EXISTE.** La cuenta ya tiene una app cargada, nombre "Turnario",
  paquete **`com.turnariopro.app`**, estado "Borrador", 0 usuarios — confirmado por el CEO: es la
  **app hermana ya construida** (otro código, la misma que sirvió de inspiración visual para el
  rediseño "Turnario Pro" de este proyecto, ver `02-backlog/backlog.md`, "Ampliación del backlog").
  El CEO decidió explícitamente **reusar ese mismo paquete** para este proyecto en vez de crear uno
  nuevo — coincide, por buena suerte, con la recomendación que ya proponía §3.2 más abajo (dada por
  el branding, sin saber todavía que ese paquete ya estaba tomado), así que el VALOR no cambia, pero
  el motivo sí: no es una propuesta libre, es una app ya registrada que hay que reusar/continuar,
  no una nueva a crear. Como estaba en Borrador y sin usuarios, no hay nada publicado que se pise.
  **Consecuencia práctica:** cuando se llegue al paso 4 (subir el primer build), tiene que subirse a
  ESE listado ya existente ("Turnario" en la consola), no crear una app nueva ahí.

**Nuevo ítem, no contemplado en la redacción original de este documento:** la captura muestra un
aviso de Google Play Console — *"Registra tus aplicaciones para la verificación de desarrolladores
de Android antes del 30 de septiembre del 2026"*. Es la verificación de desarrolladores de Android
ya mencionada en el paso 5 de §2 (`../03-arquitectura/plan-produccion.md` §8), pero con una fecha
límite concreta y ya notificada a esta cuenta puntual — no bloquea nada de este documento hoy, pero
conviene que el CEO no lo deje pasar por estar enfocado en Turnario Pro. **VERIFICAR el estado
exacto de este trámite directamente en Play Console** (el aviso solo constata que hace falta
registrar las apps, no que ya esté completo) antes de asumir que está resuelto.

Con esto, la secuencia real que queda pendiente arranca en el **paso 2** de la tabla de §1 (generar
`android/`) — ya en curso, delegado a un agente de Mobile. El resto de §2 y §3.2 de abajo se
conserva sin editar como registro histórico de la recomendación original (útil si algún día hace
falta entender el razonamiento), pero ya no son acciones pendientes.

## 2. Cuenta de Google Play Developer (CEO — dinero real, ningún agente puede hacerlo)

1. Entrar a [play.google.com/console](https://play.google.com/console/) con la cuenta de Google
   que va a administrar la publicación (puede ser la misma cuenta que ya se usó para el proyecto de
   Google Cloud de `./google-oauth.md` §2 Paso 1, o una distinta — decisión del CEO).
2. **Costo: USD 25, pago único, sin renovación anual** (`../03-arquitectura/plan-produccion.md`
   §8) — con tarjeta del CEO, ningún agente puede completar este pago.
3. **Tipo de cuenta — decisión del CEO, no la resuelve este documento:**
   - **Personal (individual):** más simple/rápido de dar de alta; verificación de identidad
     mediante documento de identidad con foto (y, según el flujo vigente al momento del alta,
     posible verificación por video/selfie).
   - **Organización (empresa):** muestra un nombre de empresa público en la ficha de la app (más
     "profesional" para un producto pago como Turnario Pro); requiere documentación legal de la
     empresa y, según el flujo vigente de Google, puede pedir un número D-U-N-S — mismo tipo de
     trámite que ya documentó CTO IA para Apple Developer Program en
     `../03-arquitectura/plan-produccion.md` §8 (Apple sí lo exige siempre para cuentas de
     organización; para Google, confirmar si sigue aplicando al momento del alta, la política
     cambió más de una vez en los últimos años).
   - Ninguna opción bloquea la otra técnicamente — es una decisión de imagen/tiempo de trámite, no
     técnica. **Se marca acá como pregunta abierta para el CEO**, no se asume ninguna de las dos.
4. **Datos que conviene tener a mano antes de empezar** (para no cortar el trámite a mitad):
   - Nombre de desarrollador público (lo que va a ver el usuario en la ficha de Play Store — ej.
     "Turnario Pro" o el nombre legal, según el tipo de cuenta elegido en el punto 3).
   - Email y teléfono de contacto (el teléfono se verifica por SMS/llamada durante el alta).
   - Dirección física.
   - Documento de identidad (cuenta Personal) o documentación legal de la empresa (cuenta
     Organización).
   - Tarjeta de crédito/débito para el pago único de USD 25.
5. **Verificación de identidad del desarrollador:** Google la exige desde 2026 antes de poder
   publicar cualquier app (`../03-arquitectura/plan-produccion.md` §8, ya documentado por CTO IA) —
   puede sumar días de demora respecto del alta inicial. Conviene iniciar este trámite cuanto antes
   precisamente por eso (mismo razonamiento que ya usó CTO IA en §7 de ese mismo documento: "el
   cuello de botella del lanzamiento es casi seguro el tiempo externo, no el trabajo técnico").

**Nada de este paso se puede adelantar ni simular** — es, junto con el paso 6 (cuenta de pagos,
§4), el único ítem 100% en manos del CEO sin ninguna parte delegable a un agente.

## 3. Prerrequisito técnico: el proyecto Flutter todavía no tiene plataforma Android

Verificado en este ciclo (no asumido): `../05-codigo/mobile` hoy solo tiene generada la carpeta
`web/` — nunca se corrió `flutter create --platforms=android .` de forma permanente. El único lugar
donde existe una carpeta `android/` es efímera, dentro del runner de CI
(`../../../.github/workflows/turnos-mobile-ci.yml`, `flutter create --platforms=android .` sin
`--org`, nunca commiteada), con un nombre de paquete temporal
(`com.example.turnos_profesionales`, el default de Flutter) que **no está pensado para publicarse**
— sirve solo para que el CI compile.

Sin esto resuelto, no hay ningún build que se pueda firmar ni subir a Play Console (§4) — es un
bloqueante real, no cosmético.

### 3.1 Generar `android/` de forma permanente

Tarea técnica que puede ejecutar un agente (Mobile/DevOps) una vez que el CEO dé el visto bueno —
no se ejecuta en este ciclo (§0). Cuando se ejecute:

```bash
cd proyectos/turnos-profesionales/05-codigo/mobile
flutter create --platforms=android --org com.turnariopro .   # o el org que confirme el CEO, ver §3.2
flutter pub get
flutter analyze
```

`flutter create` sobre un proyecto existente **no pisa** `pubspec.yaml` ni `lib/` (mismo mecanismo
que ya usa el CI, ver `../05-codigo/mobile/README.md`) — solo agrega lo que falta. Dos detalles a
verificar en el mismo momento de ejecutar esto, no asumidos a ciegas:

- **El `--org` de `flutter create` no produce por sí solo el `applicationId` final deseado.**
  `pubspec.yaml` declara `name: turnos_profesionales` (el nombre interno del paquete Dart, no el
  branding) — `flutter create --org com.turnariopro .` arma el `applicationId` concatenando
  `<org>.<name>`, es decir **`com.turnariopro.turnos_profesionales`**, no
  `com.turnariopro.app` (§3.2). Para llegar exactamente al valor recomendado en §3.2 hace falta un
  paso manual más, chico y estándar: editar `applicationId` (y `namespace`, en Android Gradle
  Plugin 8+) dentro de `android/app/build.gradle` después de generar la carpeta. No es un hack —
  es la forma normal de fijar un `applicationId` distinto del que arma `flutter create` por
  default.
- **Re-generar íconos/splash después:** `../05-codigo/mobile/flutter_launcher_icons.yaml` ya tiene
  la sección `android:` completa y comentada explícitamente como "pendiente de
  `flutter create --platforms=android .`" (branding real: degradado azul→violeta con una "T"
  fusionada a un motivo de reloj, `assets/icon/`) — apenas exista `android/`, correr
  `dart run flutter_launcher_icons` (y `dart run flutter_native_splash:create`) para que el ícono
  real quede aplicado en `android/app/src/main/res/`, no el ícono default de Flutter.
- **Revisar/completar `.gitignore` de `android/` antes del primer commit** — el `.gitignore` propio
  de `05-codigo/mobile` (raíz del proyecto Flutter) hoy no tiene ninguna entrada específica de
  Android (lógico: la carpeta no existe todavía). Antes de commitear la keystore (§3.3), confirmar
  que `android/key.properties` y cualquier `*.jks`/`*.keystore` queden explícitamente ignorados —
  no asumir que la plantilla que genera `flutter create` ya lo cubre sin revisarlo.
- Solo `--platforms=android` — no `android,ios`: D15 (`../01-requisitos/documento-funcional.md`,
  ya confirmada por el CEO) fija el lanzamiento inicial solo Android, mismo criterio que ya aplicó
  `./google-oauth.md` §2 Paso 5 para no crear el Client ID iOS todavía.

### 3.2 `applicationId` — recomendación de DevOps, pendiente de confirmación del CEO (no aplicada)

**Recomendación: `com.turnariopro.app`.**

Razonamiento:
- Coherente con el branding ya elegido y ya integrado en el proyecto — el ícono real
  (`assets/icon/icon.png` y variantes) y el nombre "Turnario Pro" ya están aplicados en Mobile
  (`../05-codigo/mobile/README.md`, sección "Branding real de la app").
- Todo en minúsculas — no es estrictamente obligatorio para Android, pero es la convención estándar
  (evita problemas de sensibilidad a mayúsculas en Gradle/herramientas de CI) y corrige el ejemplo
  con mayúscula media (`com.turnarioPro.app`) que había quedado anotado como ilustrativo, sin
  decidir, en `./google-oauth.md` §2 Paso 4.
- No hay un dominio propio registrado para este proyecto (no se encontró ninguna referencia a uno
  en el repo) — usar el nombre de marca como pseudo-dominio invertido es la práctica estándar para
  apps sin dominio propio todavía (el propio repositorio de GitHub del proyecto ya usa
  "TurnarioPro" como nombre, ver `matiasayago/TurnarioPro` en los links de CI).

**Por qué esto es la decisión de mayor impacto de todo este documento:** igual que ya explicó
`./google-oauth.md` §2 Paso 4, el nombre de paquete de una app Android es, en la práctica,
**permanente** una vez que se sube el primer build a Play Console (§4) — cambiarlo después implica
publicar como una app nueva, perdiendo reseñas/instalaciones/el propio listado. Por eso se deja acá
como **propuesta concreta, no aplicada** — no se genera `android/` (§3.1) ni se le pide nada a
Mobile todavía con este valor hasta que el CEO lo confirme explícitamente.

**Beneficio colateral de resolver esto ahora:** desbloquea también el ítem que `./google-oauth.md`
§2 Paso 4 dejó pendiente para el Client ID OAuth de tipo "Android" (necesita el mismo
`applicationId` + un SHA-1 de firma) — confirmar el paquete acá resuelve las dos dependencias con
una sola decisión del CEO, no dos por separado.

### 3.3 Keystore de firma — tarea técnica (a diferencia de §2, esto sí puede ejecutarlo un agente)

Android exige que **todo** build subido a Play Console esté firmado con una clave real — Play
Console rechaza de forma explícita cualquier APK/AAB firmado con el certificado de debug estándar
(el `debug.keystore` que genera automáticamente cualquier instalación de Android Studio/Gradle,
con contraseña pública y conocida — "androiddebugkey"/"android"), incluso para subir solo al track
de Internal testing (§4). No existe hoy ninguna keystore de release/subida en este proyecto (mismo
gap que ya había detectado `./google-oauth.md` §2 Paso 4).

**Quién lo hace:** a diferencia de la cuenta de Play Developer (§2), generar una keystore es un
comando local (`keytool`, parte del JDK que ya requiere el toolchain de Android/Flutter) — no
requiere ninguna cuenta ni ningún pago. Un agente (Mobile/DevOps) puede ejecutarlo una vez que el
CEO dé el visto bueno, junto con §3.1. Ejemplo del comando (ilustrativo, valores reales a definir
al ejecutar):

```bash
keytool -genkey -v -keystore turnario-pro-upload-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias turnario_pro_upload
```

**Lo que NO puede hacer un agente es custodiar el resultado a largo plazo.** El archivo `.jks`
resultante y sus dos contraseñas (store password, key password) son un secreto que tiene que
sobrevivir más allá de cualquier sesión/entorno de trabajo de un agente — recomendación: generarla,
entregarle el archivo + contraseñas al CEO (o a quien administre los secretos del proyecto) de
inmediato, y que se resguarden fuera del repo (gestor de contraseñas / backup cifrado) — nunca
commitear `*.jks`/`*.keystore`/`android/key.properties` (§3.1, último punto).

**Recomendación: habilitar Play App Signing** (la opción que ya ofrece Play Console por default al
subir el primer build) — Google pasa a custodiar la clave de firma real de la app, y lo que el
proyecto conserva es solo una "clave de carga" (upload key, la que genera el comando de arriba).
Consecuencia práctica de esta elección: si algún día se pierde la keystore de carga, hay un proceso
de recuperación vía soporte de Play Console (con verificación de identidad, toma tiempo pero es
posible). **Sin Play App Signing**, perder la keystore real es prácticamente irreversible: nunca
más se podría actualizar esa misma app en Play Store (habría que publicarla de cero, perdiendo
reseñas/instalaciones) — mismo tipo de consecuencia permanente que ya se documentó para el
`applicationId` en §3.2.

## 4. Publicar un build inicial en Play Console (Internal testing)

Google Play Billing exige que la app ya exista como entidad en Play Console — aunque sea sin
publicarse al público — antes de habilitar la sección de productos de suscripción (§5). Orden
recomendado (a verificar contra la consola vigente al momento de ejecutarlo — mismo criterio de
"VERIFICAR" que ya usa este proyecto para Render/Google Cloud, ver `./google-oauth.md` §2):

1. **Crear la app en Play Console** ("Crear app"): nombre ("Turnario Pro"), idioma default, tipo
   "App" (no "Juego"), "Gratuita" (la app en sí es gratis — el modelo freemium vive en la
   suscripción, no en el precio de descarga, `../02-backlog/backlog.md` HU-29).
2. **Completar los cuestionarios obligatorios de ficha de la app** — más largos de lo que parece a
   primera vista: clasificación de contenido, público objetivo, formulario de seguridad de datos
   ("Data safety", qué datos recolecta la app — este proyecto ya maneja datos personales y, si
   HU-20 llega a producción con datos de salud, datos sensibles, ver
   `../03-arquitectura/plan-produccion.md` §9), declaración de anuncios (esta app no tiene), y la
   URL de política de privacidad (ya señalada como pendiente compartido en
   `../03-arquitectura/plan-produccion.md`, ítem B9, y en `./google-oauth.md` §2 Paso 2, punto 6).
   Ninguno de estos formularios lo puede completar un agente por su cuenta — son afirmaciones
   legales sobre el producto real, las tiene que revisar/aprobar el CEO (con Technical
   Writer/Business Analyst si hace falta redactar el texto).
3. **Generar y subir un build firmado** al track **Internal testing** (el más rápido — sin revisión
   de Google, a diferencia de producción):
   ```bash
   flutter build appbundle --release
   ```
   firmado con la keystore de §3.3 y el `applicationId` confirmado en §3.2. Android App Bundle
   (`.aab`), no APK — es el formato que exige Play Console para apps nuevas.
4. **Agregar al menos un tester interno** (un email/cuenta de Google — puede ser la del propio
   CEO) para que la app quede instalable en ese track.
5. **Completar "Configuración de monetización"** — vincular una cuenta de pagos de Google
   (Google Payments merchant account) para poder cobrar y recibir el dinero de las suscripciones.
   Este paso pide datos bancarios/fiscales reales — **acción del CEO**, del mismo tipo que el alta
   de la cuenta de Mercado Pago ya documentada en `../03-arquitectura/plan-produccion.md` ítem B7
   (KYC/CUIT/cuenta bancaria), ningún agente puede completarlo.

Recién con los 5 pasos de arriba resueltos, la sección "Monetizar → Productos → Suscripciones" de
Play Console queda disponible para crear productos reales (§5).

## 5. Productos de suscripción en Play Console

**Aviso importante para quien ejecute esto:** Play Console dejó de manejar cada precio como un
"SKU" totalmente independiente hace varios años — el modelo vigente (Play Billing Library 5+) es
**un único producto de suscripción, con uno o más "planes base" (base plans) adentro**, cada uno
con su propio precio y período de facturación. Google además maneja nativamente el cambio entre
planes base del mismo producto (con prorrateo), lo cual encaja bien con "mensual ↔ anual" siendo
el mismo producto. Confirmar que esto siga siendo así en la consola vigente al momento de
ejecutarlo (mismo criterio de "VERIFICAR" del resto de este documento) — si Google volvió a
cambiar el modelo, ajustar la secuencia de abajo, no el resultado esperado (2 opciones de precio
para el usuario, resueltas del lado servidor).

### IDs recomendados (a aplicar recién cuando el CEO ejecute este paso — no se crea nada acá)

| Concepto | ID recomendado | Reglas de Play Console (a confirmar vigentes) |
|---|---|---|
| Producto de suscripción (contenedor) | `turnario_pro` | minúsculas, dígitos, `_`/`.`, empieza con letra/dígito, hasta 40 caracteres, inmutable una vez creado |
| Plan base — mensual | `mensual` | minúsculas, dígitos, `-`, empieza con letra, hasta 63 caracteres, único dentro del producto |
| Plan base — anual | `anual` | ídem |

Para que Backend/Mobile tengan un identificador único y estable por plan en código (constantes,
logs), combinarlos como `turnario_pro_mensual` / `turnario_pro_anual` (alias interno del par
`productId=turnario_pro` + `basePlanId=mensual|anual`) — son los mismos 2 nombres que ya sugería
la consigna de este ciclo, mapeados a la estructura real de dos niveles que usa Play Console hoy.

### Precios (valores ya decididos por el CEO en `../02-backlog/backlog.md`, HU-29 — no se
re-derivan acá, solo se calcula el número exacto pedido)

- **Mensual: USD 9.00.**
- **Anual: USD 86.40** (= 9 × 12 × 0.80, 20% de descuento sobre el equivalente de pagar 12 meses
  sueltos) — facturado una sola vez al año. Equivale a **USD 7.20/mes**, un ahorro de
  **USD 21.60/año** (~2.4 meses gratis) frente a pagar mes a mes.
- Play Console permite fijar el precio en una moneda (ej. USD) y auto-generar la conversión al
  resto de las monedas/países, con posibilidad de ajustar manualmente cada una después — no hace
  falta cargar un precio en pesos a mano si no se quiere.
- **Nota financiera para el CEO, no bloqueante:** Google retiene una comisión sobre lo cobrado
  (históricamente 15% para la mayoría de los desarrolladores, ver la sección de comisiones de Play
  Console al momento de configurar el producto — confirmar el porcentaje vigente ahí mismo, no
  asumido a ciegas acá) — el ingreso neto del negocio es el precio de lista menos esa comisión.

### Secuencia dentro de Play Console (a verificar contra la interfaz vigente)

1. Monetizar → Productos → Suscripciones → Crear suscripción, ID `turnario_pro`, nombre visible
   "Turnario Pro" (el que ve el usuario en el diálogo de compra de Google).
2. Dentro de esa suscripción, crear 2 planes base: `mensual` (facturación cada 1 mes, USD 9.00) y
   `anual` (facturación cada 1 año, USD 86.40).
3. Publicar ambos planes base (quedan en borrador hasta que se publican explícitamente — no
   quedan disponibles para compra real solo por crearlos).

## 6. Cuenta de servicio (Service Account) para verificación server-side

Mismo principio de seguridad que ya aplicó este proyecto en otros lados (nunca confiar un valor sin
re-derivarlo del lado del servidor — mismo espíritu que la verificación de RLS o la del ID token de
Google en `./google-oauth.md` §1): Backend **no puede confiar** en que Mobile le diga "la compra se
hizo" — tiene que confirmarlo contra la API de Google con una credencial propia del servidor.

**Paralelo directo con el flujo ya implementado de HU-35, para ubicarse rápido:**

| HU-35 (OAuth, ya implementado) | HU-29 (Play Billing, este documento) |
|---|---|
| Mobile obtiene un **ID token** del SDK de Google Sign-In | Mobile obtiene un **purchaseToken** de la Play Billing Library tras la compra |
| Mobile se lo manda a Backend | Mobile se lo manda a Backend (endpoint a definir, ej. `POST /negocios/:id/suscripcion/verificar`) |
| Backend verifica el JWT con `google-auth-library` (`OAuth2Client.verifyIdToken`), sin credencial propia — solo el `GOOGLE_CLIENT_ID` público | Backend verifica el `purchaseToken` llamando a la **Android Publisher API** de Google, autenticado con una **credencial propia del servidor** (esto sí, a diferencia de OAuth) |

La diferencia de fondo: verificar un ID token es criptografía local (Google publica claves
públicas); verificar una compra real requiere preguntarle a Google directamente "¿este token de
compra es válido y sigue activo?" — eso exige una identidad de servidor autorizada, no solo una
librería.

### 6.1 Qué es y cómo se crea (instructivo para el CEO)

1. **Reutilizar el proyecto de Google Cloud que ya existe**, en vez de crear uno nuevo — el mismo
   que se dio de alta en `./google-oauth.md` §2 Paso 1 para HU-35 (ej. "Turnos Profesionales"). No
   es obligatorio, pero evita duplicar proyectos sin necesidad; decisión del CEO si prefiere
   separarlos.
2. En **Play Console → Configuración → Acceso a la API** ("Setup → API access"): esta pantalla
   vincula el proyecto de Google Cloud del punto 1 con la cuenta de Play Developer de §2. Si
   todavía no hay ningún proyecto vinculado, Play Console lo ofrece hacer ahí mismo.
3. En esa misma pantalla, sección **"Cuentas de servicio"**: "Crear nueva cuenta de servicio" — da
   un link directo a Google Cloud Console (IAM y administración → Cuentas de servicio) con el
   proyecto correcto ya seleccionado.
4. En Google Cloud Console: **Crear cuenta de servicio** (nombre sugerido:
   `turnos-profesionales-play-billing`), sin necesidad de asignarle ningún rol de IAM especial ahí
   — el permiso real se otorga después, desde Play Console (punto 6). Confirmar también que la API
   **"Google Play Android Developer API"** quede habilitada en ese proyecto (Play Console suele
   ofrecer el link directo para activarla en el mismo flujo).
5. Dentro de esa cuenta de servicio: pestaña **"Claves" ("Keys")** → "Agregar clave" → "Crear clave
   nueva" → **JSON**. Se descarga un archivo `.json` — **esta es la credencial sensible**, el
   equivalente de este flujo a lo que es un `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET` para OAuth,
   pero más sensible todavía (con este archivo, quien lo tenga puede consultar y, según el permiso
   que se le otorgue, incluso actuar en nombre de la cuenta de Play Developer).
6. De vuelta en Play Console → **"Usuarios y permisos"**: invitar a la cuenta de servicio como
   usuario (su "email" tiene forma
   `nombre@proyecto.iam.gserviceaccount.com`) y otorgarle el permiso mínimo necesario para
   **consultar** el estado de compras/suscripciones de esta app puntual — no permisos de
   administración ni de otras apps. El nombre exacto del permiso en la interfaz vigente puede variar
   (Google lo renombró más de una vez); buscar algo del estilo "Ver datos financieros" / "Gestionar
   pedidos y suscripciones" acotado a la app "Turnario Pro" — **VERIFICAR contra la consola real al
   momento de ejecutar esto**, no asumir un nombre de memoria.

### 6.2 Qué necesita Backend, y con qué (recomendación técnica, no implementada en este ciclo)

Backend ya depende de `google-auth-library` (`../05-codigo/backend/package.json`, usado hoy para
HU-35) — **recomendación: reusar esa misma librería para autenticar contra la Android Publisher
API, en vez de sumar la dependencia completa `googleapis`** (mismo criterio que ya aplicó
`./google-oauth.md` §1 para OAuth: "alcanza con la librería chica, no hace falta la completa").
`google-auth-library` puede construir un cliente autenticado a partir del JSON de la cuenta de
servicio (`GoogleAuth`/`JWT`, scope `https://www.googleapis.com/auth/androidpublisher`) y hacer el
`request()` HTTP directo contra el endpoint REST, sin necesitar el cliente generado de `googleapis`:

```ts
// Ilustrativo — la implementación final es de Backend, a confirmar en su momento.
const auth = new GoogleAuth({
  credentials: JSON.parse(process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON!),
  scopes: ['https://www.googleapis.com/auth/androidpublisher'],
});
const client = await auth.getClient();
const { data } = await client.request({
  url: `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
       `${process.env.GOOGLE_PLAY_PACKAGE_NAME}/purchases/subscriptionsv2/tokens/${purchaseToken}`,
});
// data.subscriptionState indica si sigue activa, cancelada, en pausa, expirada, etc.
```

Endpoint recomendado: `purchases.subscriptionsv2.get` (Android Publisher API v3) — el que devuelve
el estado completo de la suscripción en una sola llamada, reemplazo del endpoint viejo
`purchases.subscriptions.get` (anterior al modelo de planes base de §5). **A confirmar contra la
documentación vigente de Google al momento de implementar** — mismo criterio de "VERIFICAR" que
usa todo este documento.

**Nota para más adelante (no bloqueante para v1, no de este ciclo):** Google recomienda no
depender solo de consultar la API bajo demanda, sino además suscribirse a notificaciones en tiempo
real (Real-time Developer Notifications vía Google Cloud Pub/Sub) para enterarse de renovaciones/
cancelaciones sin esperar a que el usuario abra la app. Queda como recomendación para cuando
Backend diseñe la implementación real, no como parte del alcance de este documento.

## 7. Qué le va a pedir DevOps a Backend (variables de entorno — planteadas, no aplicadas en este ciclo)

Lista concreta para cuando Backend arranque la implementación real (ver §0 para por qué
`.env.example`/`render.yaml` no se tocan todavía):

| Variable | Tipo | Sale de | Notas |
|---|---|---|---|
| `GOOGLE_PLAY_PACKAGE_NAME` | No secreta | `applicationId` confirmado (§3.2) | La usa cada llamada a la Android Publisher API (`packageName`) — mismo valor que Mobile compila en el build real. |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | **Secreta** | El archivo `.json` de §6.1, punto 5 | Recomendación: todo el contenido del JSON como string en una variable de entorno (mismo mecanismo que ya usa este proyecto — nunca en el repo). Alternativa a evaluar en su momento: "Secret Files" de Render, que monta contenido como archivo en vez de variable de texto — **a confirmar contra el dashboard vigente de Render**, no usado todavía en este proyecto. |
| `GOOGLE_PLAY_SUBSCRIPTION_PRODUCT_ID` | No secreta | `turnario_pro` (§5), una vez creado en Play Console | No es secreto, pero conviene fijarlo en una sola variable/constante compartida para que Backend y Mobile no lo hardcodeen cada uno por su lado con el riesgo de que diverjan. |

Gestión por entorno, cuando corresponda: mismo patrón ya establecido en este proyecto para
`GOOGLE_CLIENT_ID` (`./google-oauth.md` §4) — local vía `.env` (gitignorado), ausente en CI (no va
a haber credenciales reales de Google Play en un runner de GitHub Actions, ni hace falta: el
endpoint de verificación puede responder 503 mientras no esté configurado, mismo criterio de
"opt-in explícito, nunca un crash silencioso" ya aplicado a `GOOGLE_CLIENT_ID`/
`ENABLE_DEV_ROUTES`), y en Render vía `sync: false` en `render.yaml` (carga manual desde el
dashboard, nunca un valor real commiteado). Se deja como recomendación para el ciclo de DevOps que
acompañe la implementación real de Backend — no aplicado ahora.

## 8. Dependencias y bloqueos (resumen)

| Ítem | Bloquea | Dueño | Estado |
|---|---|---|---|
| Cuenta de Google Play Developer (USD 25 + verificación de identidad) | Todo lo demás de este documento | CEO | **Hecho** (ver §1bis) — cuenta Personal, "Matias Sayago", ya existente |
| Generar `android/` de forma permanente (§3.1) | Confirmar `applicationId` "en firme", generar keystore, armar un build subible | Mobile/DevOps | **En curso** (delegado, 2026-08-14) |
| Confirmar `applicationId` definitivo (§3.2) | Generar `android/` con el valor correcto desde el inicio; también desbloquea el Client ID Android de OAuth ya pendiente en `./google-oauth.md` §2 Paso 4 | CEO | **Hecho** (ver §1bis) — `com.turnariopro.app`, reusando la app "Turnario" (hermana) ya existente en Play Console |
| Verificación de desarrolladores de Android (deadline 30/09/2026, ver §1bis) | Publicar cualquier app desde esa fecha | CEO | Pendiente — VERIFICAR estado exacto en Play Console, no asumido completo solo por la existencia del aviso |
| Keystore de firma + Play App Signing (§3.3) | Subir cualquier build a Play Console | Mobile/DevOps (técnico); custodia del archivo, CEO | Pendiente |
| App creada en Play Console + build firmado en Internal testing + Monetización configurada (§4) | Crear productos de suscripción reales (§5) | CEO (alta, cuestionarios, cuenta de pagos) + Mobile/DevOps (build) | Pendiente |
| Producto `turnario_pro` con planes base `mensual`/`anual` (§5) | Que exista algo real para que Backend verifique | CEO (lo crea en Play Console; IDs y precios ya propuestos acá) | Pendiente |
| Cuenta de servicio + JSON key para la Android Publisher API (§6) | Verificación server-side de Backend | CEO (crea la cuenta de servicio y le otorga permisos, con guía paso a paso) | Pendiente |
| Implementación de Backend (endpoint de verificación, modelo de datos de suscripción) | Que HU-29 funcione de punta a punta | Backend (con DBA para el modelo de datos, no tocado por este documento) | No empieza en este ciclo — puede diseñarse/mockearse en paralelo, pero no probarse contra algo real hasta que exista al menos §6 |
| Implementación de Mobile (Play Billing Library, pantalla de upgrade) | Que HU-29 funcione de punta a punta | Mobile | Puede diseñar la UI ya; una compra real necesita `applicationId` real + producto real de Play Console |

## 9. Checklist para el CEO (resumen ejecutivo, sin tecnicismos)

- [x] ~~Decidir si la cuenta de Google Play Developer va a ser Personal o de Organización~~ — ya
      existe, es Personal (ver §1bis).
- [x] ~~Crear la cuenta en play.google.com/console y pagar los USD 25~~ — ya existe (ver §1bis).
- [x] ~~Confirmar el nombre de paquete (`applicationId`)~~ — **`com.turnariopro.app`**, confirmado
      (ver §1bis): es la app "Turnario" ya existente en tu cuenta (la app hermana), reusada a
      propósito para este proyecto, no una nueva.
- [ ] **Nuevo, con fecha límite:** verificar en Play Console el estado real de la "verificación de
      desarrolladores de Android" (deadline 30/09/2026, ver §1bis) — el aviso que viste solo dice
      que hace falta registrarse, no que ya esté hecho.
- [ ] Generar la plataforma Android y la keystore de firma (tareas técnicas, las hace un agente —
      §3.1/§3.3) — ya en curso para la plataforma; vos solo tenés que guardar de forma segura el
      archivo de la keystore y sus contraseñas cuando te los entreguemos (todavía no generada).
- [ ] Completar los cuestionarios de ficha de la app "Turnario" ya existente (clasificación de
      contenido, seguridad de datos, etc. — §4) y subir el primer build al track de Internal
      testing.
- [ ] Completar la configuración de monetización (cuenta de pagos de Google, con tus datos
      bancarios/fiscales — §4).
- [ ] Crear el producto de suscripción "Turnario Pro" con sus 2 planes (mensual USD 9.00, anual
      USD 86.40) en Play Console — IDs e importes ya calculados en §5.
- [ ] Crear la cuenta de servicio para que Backend pueda verificar compras reales, y darle el
      permiso mínimo necesario (§6) — instructivo paso a paso en esa sección.
- [ ] Entregar a Backend/DevOps el archivo JSON de la cuenta de servicio y el nombre de paquete
      final, para cargarlos como variables de entorno (nunca en el repo) cuando Backend arranque
      la implementación real (§7).

## 10. Registro de este ciclo (motivo, cambios, forma de rollback)

**Motivo:** el CEO confirmó avanzar con HU-29 ("Turnario Pro", `../02-backlog/backlog.md`, E11) —
correspondía a DevOps preparar la guía de credenciales/cuentas reales necesarias, mismo tipo de
tarea que ya resolvió para HU-35 (`./google-oauth.md`), antes de que Backend/Mobile puedan empezar
a construir contra algo real.

**Cambios incluidos:**
- Este documento (nuevo).
- `../../../memory/proyectos/turnos-profesionales/decisiones.md` — entrada nueva con el resumen de
  este plan, para que otros agentes la reutilicen sin releer el documento completo.

**No se tocó:** ningún archivo de `05-codigo/` (Backend, Mobile ni DBA), `.env.example`,
`render.yaml`, ni `02-backlog/backlog.md` — ver §0 para el razonamiento completo de por qué este
ciclo, a diferencia del de OAuth, no declara todavía las variables de entorno futuras (§7 las deja
planteadas para el próximo ciclo, cuando exista código real que las consuma). No se creó ninguna
cuenta, no se realizó ningún pago, no se generó ninguna keystore ni ninguna carpeta `android/` real
— ver §0/§1.

**Forma de rollback:** revertir este documento y la entrada de memoria — ambos son puramente
documentación/planificación, sin ninguna credencial ni configuración real todavía en ningún
entorno. Ningún cambio de este ciclo llega a producción ni afecta nada desplegado hoy
(`https://turnos-profesionales-backend.onrender.com` sigue sin ninguna relación con este
documento). Ningún paso de este plan se ejecuta sin aprobación previa del Director General IA/CEO
(`../../../docs/04-manual-operativo.md`, reglas de actuación de DevOps).
