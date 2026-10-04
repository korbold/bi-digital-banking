# ADR 0001 — Monorepo modular por dominios

## Problema
La plataforma debe evolucionar hacia "múltiples dominios funcionales administrados por equipos independientes".
Un único paquete Flutter acopla todo: cualquier cambio recompila y re-testea el mundo, los límites entre
dominios se erosionan (imports cruzados) y no hay forma de asignar ownership.

## Alternativas evaluadas
| Opción | A favor | En contra |
|---|---|---|
| Un solo paquete con carpetas por feature | Cero fricción inicial | Límites sólo por convención; imports cruzados inevitables |
| **Monorepo con paquetes por dominio (pub workspaces + melos)** | Límites forzados por el `pubspec` (si no está declarado, no se puede importar); una sola resolución de dependencias; CI y refactors atómicos | Algo más de boilerplate; requiere disciplina de API pública (`lib/<pkg>.dart`) |
| Multi-repo (un repo por dominio, paquetes versionados) | Autonomía total por equipo | Versionado/publicación interna, "diamond dependencies", cambios transversales lentos. Prematuro para el tamaño actual |
| Flutter add-to-app / módulos nativos por equipo | Equipos nativos independientes | Complejidad de build alta, no aporta en un equipo Flutter |

## Decisión
Monorepo con **pub workspaces** (Dart ≥ 3.6) y **melos** para scripts. Capas:

```
app (composition root: DI, router, Firebase)
 ├─ feature_auth · feature_accounts · feature_home · feature_miniapps · feature_notifications   ← dominios
 ├─ sdui                                                                                           ← motor de UI dinámica
 └─ core · core_network · design_system                                                            ← plataforma compartida
```
Reglas: los `feature_*` **no se importan entre sí**; sólo dependen de paquetes de plataforma. El app shell
es el único que conoce a todos y los compone (p. ej. registra `AccountSummarySection` de accounts en el registro SDUI de home).

## Trade-offs
- (+) Un equipo puede trabajar en `feature_accounts` sin tocar ni compilar mentalmente el resto; los tests corren por paquete.
- (+) La dependencia prohibida falla en `flutter pub get`/analyzer, no en code review.
- (−) Más archivos `pubspec.yaml` que mantener; versiones de dependencias deben alinearse (la resolución única lo garantiza).

## Impacto a largo plazo
Si un dominio crece hasta necesitar ciclo de release propio, su paquete ya tiene API pública y tests aislados:
puede extraerse a otro repo y consumirse por versión sin reescribir. CODEOWNERS por carpeta da ownership inmediato.
