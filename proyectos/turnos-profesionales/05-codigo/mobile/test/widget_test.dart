// `flutter create --platforms=android .` (generación de la plataforma Android, ver
// proyectos/turnos-profesionales/08-despliegue/google-play-billing.md §3.1) regenera este
// archivo con la plantilla genérica de Flutter (una contra-app de ejemplo "MyApp" tipo
// contador) — no existe en este proyecto real (ver lib/main.dart, `TurnosProfesionalesApp`),
// así que esa plantilla rompe `flutter analyze` (referencia una clase inexistente). Con
// android/ ahora permanente en el repo, se resuelve dejando acá un placeholder mínimo sin
// ninguna dependencia del árbol de widgets real de la app — evita acoplar este archivo a
// pantallas/estado que otras rondas de Mobile pueden estar modificando en paralelo (fuera del
// alcance de esta tarea, que es solo la plataforma Android). `.github/workflows/turnos-mobile-ci.yml`
// ya no borra este archivo (ese paso era del período en que android/ —y por lo tanto este
// archivo— se generaba de forma efímera en cada corrida de CI; dejó de aplicar el mismo día
// que este archivo se commiteó). Reemplazar por una suite de tests real es trabajo aparte, no
// de este ciclo.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placeholder — sin suite de tests de la app todavía', () {
    expect(1 + 1, 2);
  });
}
