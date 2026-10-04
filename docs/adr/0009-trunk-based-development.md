# ADR 0009 — Trunk Based Development

## Problema
La prueba exige TBD y evalúa frecuencia y calidad del historial. En equipos con varios dominios, las ramas
largas generan merges dolorosos y releases riesgosos.

## Decisión
- Una sola rama de larga vida: `main`, siempre desplegable.
- Commits pequeños y frecuentes directamente a `main` (o ramas de vida < 1 día con PR cuando hay revisión).
- Conventional Commits (`feat(accounts): ...`) ⇒ changelog y versionado automatizables.
- Trabajo incompleto oculto tras **feature flags** (Remote Config) en lugar de ramas.
- **CI como gate** en cada push: formato, análisis estático, tests unitarios/widget con cobertura, typecheck y tests del BFF, build del APK.
- Releases por *tag* desde `main` (`vX.Y.Z`), nunca ramas de release de larga vida.

## Trade-offs
(+) Integración continua real, conflictos mínimos. (−) Exige CI rápido y disciplina de flags; un commit roto bloquea a todos
⇒ se revierte primero, se investiga después.

## Evidencia en este repo
`git log --oneline` muestra la evolución incremental por dominio; `.github/workflows/ci.yml` es el gate.
