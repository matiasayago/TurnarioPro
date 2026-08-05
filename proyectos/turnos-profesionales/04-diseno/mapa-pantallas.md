# Mapa de Pantallas y Flujos — Turnos Profesionales

**Rol:** UX/UI
**Fase:** 3 — Diseño
**Entradas:** `01-requisitos/documento-funcional.md` (casos de uso), `02-backlog/backlog.md`

## 1. Principio de diseño

Una sola app Flutter con **dos modos** según el rol del usuario autenticado (Cliente /
Profesional) — no dos apps separadas. El modo se determina en el login y no es
intercambiable por el usuario (un profesional no "cambia" a modo cliente en este alcance).

## 2. Mapa de navegación — modo Cliente

```
Login / Registro
   │
   ▼
Buscar Negocios ──► Detalle de Negocio (servicios) ──► Elegir Profesional
                                                              │
                                                              ▼
                                                    Horarios Disponibles
                                                              │
                                                              ▼
                                              Confirmar Turno (+ pago si aplica, D2)
                                                              │
                                                              ▼
                                                     Mis Turnos ──► Detalle de Turno
                                                                        │
                                                          ┌─────────────┴─────────────┐
                                                          ▼                           ▼
                                                     Cancelar                  Reprogramar
```

Pantallas: **Buscar Negocios** (HU-00b), **Detalle de Negocio** (HU-07), **Elegir
Profesional** (HU-08), **Horarios Disponibles** (HU-09), **Confirmar Turno / Pago** (HU-09b),
**Mis Turnos** (HU-12, HU-13).

## 3. Mapa de navegación — modo Profesional

```
Login
   │
   ▼
Agenda (calendario semanal: turnos + slots libres) ──► Detalle de Turno
   │                                                          │
   ├──► Definir Disponibilidad (por servicio)                └──► (ver datos del cliente)
   │
   ├──► Excepciones (bloqueo puntual)
   │
   ├──► Mis Clientes ──► Historial de Visitas del cliente
   │
   └──► Configuración de Servicios (asociar servicios, flag "requiere seña" — HU-04b)
```

Pantallas: **Agenda** (HU-06), **Definir Disponibilidad** (HU-05), **Excepciones** (HU-15),
**Mis Clientes** (HU-10), **Historial de Visitas** (HU-11), **Configuración de Servicios**
(HU-04b).

## 4. Wireframe conceptual — Horarios Disponibles (Cliente)

```
+-----------------------------------------------------+
| < Volver          Dr. García — Consulta general      |
+-----------------------------------------------------+
| Jue 7 ago  | Vie 8 ago  | Lun 11 ago | Mar 12 ago    |
+-----------------------------------------------------+
|  10:00     |  09:30     |  (sin lugar)| 14:00        |
|  10:30     |  11:00     |             | 14:30        |
|  ...       |  ...       |             | ...          |
+-----------------------------------------------------+
| ⓘ No hay lugar en los próximos días elegidos —       |
|   próximo horario disponible: Mar 12, 14:00 (D5)     |
+-----------------------------------------------------+
|              [ Reservar 10:00 - Jue 7 ]              |
+-----------------------------------------------------+
```

## 5. Wireframe conceptual — Agenda (Profesional)

```
+-----------------------------------------------------+
| Agenda semanal            [Definir disponibilidad]  |
+-----------------------------------------------------+
| Lun | Mar | Mié | Jue | Vie | Sáb | Dom              |
|-----+-----+-----+-----+-----+-----+------            |
| 9:00 María P.   |     |Juan R.|    |     |            |
| 9:30 (libre)    |     |(libre)|    |     |            |
| ...                                                   |
+-----------------------------------------------------+
| [Mis Clientes]   [Excepciones]   [Config. Servicios] |
+-----------------------------------------------------+
```

## 6. Consideraciones de diseño

- Soporte de tema claro/oscuro y diseño responsive (estándar de la empresa, ver
  `docs/07-portal-ceo.md` §10, aplicado también aquí como buena práctica transversal).
- El flag "requiere seña" de un servicio debe ser visible para el cliente **antes** de elegir
  el horario, no como sorpresa al confirmar (transparencia de precio).
- El estado "pendiente de pago" debe mostrarse explícitamente en "Mis Turnos" con un
  contador/aviso de expiración (ver `documento-arquitectura.md` §3, expira en 15 min).

## 7. Pendiente

Mockups visuales (Figma) quedan fuera de este documento — este mapa habilita a Frontend/Mobile
a arrancar la maquetación funcional mientras se producen los mockups de alta fidelidad.
