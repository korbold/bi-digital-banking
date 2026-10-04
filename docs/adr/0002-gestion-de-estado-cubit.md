# ADR 0002 — Gestión de estado con Cubit

## Problema
Pantallas con estados ricos (cargando, datos frescos, datos en caché con error de refresco, falla total)
que deben ser predecibles, testeables y homogéneos entre equipos.

## Alternativas evaluadas
| Opción | A favor | En contra |
|---|---|---|
| **Cubit (flutter_bloc)** | Estados inmutables explícitos, `bloc_test` maduro, curva baja, estándar en banca | Algo de boilerplate en estados |
| Bloc con eventos | Trazabilidad de eventos, transformers (debounce) | Más ceremonia para flujos simples |
| Riverpod | DI + estado integrados, muy flexible | Mezcla DI con estado; más difícil imponer un patrón único entre equipos |
| Provider / setState | Simple | No escala a estados degradados complejos |

## Decisión
**Cubit** en todos los features. Bloc con eventos queda permitido donde se necesiten transformers.
Estados modelados como clases selladas / `Equatable`, incluyendo explícitamente el caso *"datos en caché + error de refresco"*.

## Trade-offs
- (+) Cada Cubit se prueba con `bloc_test` sin widgets (`expect: [loading, loaded(stale)]`).
- (+) La oferta del rol menciona Cubit: alineado al stack del equipo.
- (−) Más clases de estado que con Riverpod.

## Impacto a largo plazo
Patrón uniforme ⇒ cualquier desarrollador se mueve entre dominios sin re-aprender. Si se migrara a Riverpod,
los repositorios (capa de datos) no cambian: sólo la capa de presentación.
