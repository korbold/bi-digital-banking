# ADR 0005 — Resiliencia ante conectividad limitada, latencia e indisponibilidad parcial

## Problema
En Ecuador es común la conectividad intermitente (ascensores, transporte, zonas rurales) y los servicios bancarios
tienen ventanas de mantenimiento. El cliente debe seguir viendo su saldo y la app nunca debe duplicar una operación.

## Alternativas evaluadas
| Opción | A favor | En contra |
|---|---|---|
| Sólo timeouts + mensaje de error | Trivial | App inútil sin red |
| SDK offline de Firestore | Offline automático | Sólo cubre Firestore; no aplica a FX, seguros, BFF |
| **Pipeline propio en `core_network`**: conectividad → circuit breaker por servicio → reintentos con backoff+jitter → caché write-through con fallback | Uniforme para cualquier servicio; observable; testeable con fakes | Código propio que mantener |
| Cola de operaciones offline (outbox) para escrituras | Permite "transferir sin red" | En banca, ejecutar una transferencia diferida sin confirmación es riesgoso: descartado para dinero, ver Riesgos |

## Decisión
`ApiClient` (paquete `core_network`):
1. **Conectividad**: sin red ⇒ `OfflineFailure` inmediato (no se espera un timeout).
2. **Circuit breaker por servicio** (`accounts`, `home`, `fx`...): 3 fallas consecutivas ⇒ abierto 15 s ⇒ falla rápida;
   luego semiabierto con una petición de prueba. Evita que un servicio caído degrade toda la app.
3. **Reintentos** sólo para errores transitorios (timeout, 5xx) con backoff exponencial y *full jitter*.
   Lecturas siempre; escrituras **sólo con `Idempotency-Key`** (el BFF guarda la respuesta por clave).
4. **Caché stale-while-revalidate** por usuario (Hive): se muestra el último dato bueno al instante y se refresca.
   La UI etiqueta "Mostrando datos guardados de 10:42" y ofrece reintentar.
5. **Recuperación**: al volver la conectividad se refresca automáticamente.
6. **Chaos interceptor** para demostrar todo lo anterior en un dispositivo real (panel "Escenarios degradados").

Matriz de comportamiento:

| Escenario | Lecturas (saldo, movimientos, home) | Escrituras (transferencia) |
|---|---|---|
| Sin red | Caché + banner offline | Bloqueada con mensaje claro; no se encola |
| Latencia alta | Caché inmediato + skeleton/refresh en segundo plano | Spinner; reintento seguro con la misma clave |
| Servicio X caído | Sólo la sección X muestra estado degradado; el resto funciona | Falla rápida (breaker) con mensaje |
| Falla intermitente | Reintento transparente | Reintento transparente e idempotente |

## Trade-offs
- (+) Comportamiento consistente en todos los dominios sin que cada equipo lo reimplemente.
- (−) Datos en caché pueden estar desactualizados: siempre se muestran con su hora y nunca se usan para validar saldo en una transferencia (eso lo decide el BFF).

## Impacto a largo plazo
Los estados del breaker y los fallbacks a caché se reportan como eventos (`breaker_open`, `served_from_cache`) ⇒
métricas de "experiencia degradada" por servicio, que son la base de los SLOs (ver `docs/operations.md`).
