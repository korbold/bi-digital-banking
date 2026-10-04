# ADR 0008 — Navegación y DI sólo en el app shell

## Problema
Si cada feature conoce el router y el contenedor de dependencias, los dominios quedan acoplados entre sí
y no se pueden probar ni extraer de forma aislada.

## Decisión
- Los paquetes `feature_*` **no dependen de go_router ni de get_it**. Exponen páginas/widgets que reciben
  dependencias por constructor y navegación por callbacks (`onGoToRegister`, `onOpenAccount`).
- El **app shell** es el *composition root*: crea `ApiClient`, repositorios y Cubits (get_it) y define las rutas (go_router)
  con *redirect* según la sesión (sin sesión → login; sin onboarding → onboarding).
- Deep links de push (`data.route`) se resuelven con el mismo router.

## Alternativas
Router y DI dentro de cada feature (más rápido al inicio, acoplamiento alto); Riverpod como DI global
(mezcla responsabilidades, ver ADR 0002).

## Trade-offs
(+) Features testeables con fakes sin levantar la app. (−) El app shell concentra el cableado; se mitiga con un archivo de rutas
y un archivo de DI por dominio.

## Impacto a largo plazo
Un dominio puede reutilizarse en otra app (p. ej. app empresas) con otro router y otras implementaciones.
