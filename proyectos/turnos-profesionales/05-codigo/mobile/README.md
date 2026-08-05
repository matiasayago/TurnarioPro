# Mobile — Turnos Profesionales (Flutter)

App única con dos modos (Cliente / Profesional) según el rol del usuario autenticado — ver
`../../04-diseno/mapa-pantallas.md`.

## ⚠️ Estado: código escrito, NO compilado ni corrido

Este entorno de desarrollo no tiene el SDK de Flutter (ni Dart standalone) instalado, así que
a diferencia del backend (que sí se instaló, corrió y se probó de punta a punta, ver
`../backend/README.md`), **este código no fue verificado con el compilador ni ejecutado**.
Se revisó manualmente buscando errores de tipos/imports, y se corrigió al menos un bug real
en esa revisión (ver más abajo), pero **antes de darlo por funcional hay que correr, como
mínimo:**

```bash
flutter pub get
flutter analyze
flutter run
```

en una máquina con el SDK de Flutter instalado.

## Bug encontrado y corregido en revisión manual

`ApiClient.get()` devuelve `Future<dynamic>`. Escribir `api.get(path) as Future<List<dynamic>>`
castea el **Future**, no el valor que resuelve, y falla en runtime (`TypeError`). Se corrigió
agregando `ApiClient.getList()` / `ApiClient.getMap()`, que esperan la respuesta y castean el
valor ya resuelto — todas las pantallas usan estos helpers, no `get()` directo con cast.

## Cómo correr contra el backend

El backend expone `http://localhost:3000` (ver `../backend/README.md`). Desde un emulador
Android, `localhost` del host se accede como `10.0.2.2` — ya configurado como default en
`lib/api_client.dart`. Desde un dispositivo físico o iOS, cambiar `ApiClient(baseUrl: ...)` en
`lib/main.dart` a la IP de la máquina que corre el backend.

## Pantallas implementadas (ver mapa completo en `04-diseno/mapa-pantallas.md`)

**Cliente:** Login, Buscar Negocios (HU-00b), Detalle de Negocio/Servicios (HU-07), Elegir
Profesional (HU-08), Horarios Disponibles (HU-09), Confirmar Turno (HU-09b), Mis Turnos
(HU-12), **Reprogramar Turno (HU-13)**.

**Profesional:** Agenda (HU-06), Definir Disponibilidad (HU-05), Excepciones (HU-15), Mis
Clientes (HU-10), Historial de Visitas (HU-11), Configuración de Servicios (HU-04b).

## Simplificaciones deliberadas de este slice (no son bugs, son alcance reducido)

- El selector de servicio en las pantallas del profesional (Disponibilidad, Excepciones,
  Configuración de Servicios) es un campo de texto libre con el ID del servicio, no un
  dropdown poblado desde la API — se resuelve en una siguiente iteración.
- No hay registro de negocio/cliente desde la app (HU-00a se hizo vía API en las pruebas del
  backend) — falta la pantalla de registro.
- No hay checkout de pago real embebido — la pantalla de Confirmar Turno solo avisa que se
  requiere seña (el backend usa un Mock de Mercado Pago, ver
  `../backend/src/integraciones/pagos.ts`).
- Tema claro/oscuro: heredado del `ThemeData`/`darkTheme` de `main.dart` (Material 3), no se
  probó visualmente por no poder correr la app.
