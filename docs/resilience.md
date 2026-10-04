# Resiliencia: conectividad limitada, alta latencia e indisponibilidad parcial

Decisión y alternativas: [ADR 0005](adr/0005-resiliencia-red.md). Este documento cubre **cómo se comporta** la app y **cómo demostrarlo**.

## Matriz de comportamiento

| Escenario | Lecturas (home, saldos, movimientos, FX) | Escrituras (transferencia) |
|---|---|---|
| **Sin conexión** | `OfflineFailure` inmediato, sin esperar timeout. Se muestra el último dato guardado con un banner: *"Sin conexión. Mostrando datos guardados de las HH:mm"*. Sin caché: `ErrorView` + Reintentar | No se envía ni se encola (en banca, una operación diferida sin confirmación es un riesgo). Mensaje: *"Sin conexión. Tu transferencia no se envió; puedes reintentar sin riesgo de duplicarla."* |
| **Latencia alta** | El caché se pinta al instante (stale-while-revalidate) y la red refresca en segundo plano. Sin caché: skeletons. Timeouts: 8 s conexión, 12 s respuesta | Botón en estado de carga. Si hay timeout, se reintenta con la **misma** `Idempotency-Key` |
| **Servicio X caído** | Sólo la sección de X se degrada: FX muestra *"Tipos de cambio no disponibles · Reintentar"* y el resto del home sigue normal. Tras 3 fallas se abre el circuit breaker de X y durante 15 s responde al instante con el caché | Falla rápida con breaker abierto. Mensaje claro, sin spinner eterno |
| **Falla intermitente** | Reintento transparente: 3 intentos con backoff exponencial y full jitter (400 ms base, 4 s tope) | Reintento transparente e **idempotente**: el BFF devuelve la respuesta guardada (`Idempotent-Replayed: true`) y nunca debita dos veces |
| **Recuperación** | `AccountsCubit` escucha `ConnectivityMonitor.onStatusChange` y recarga al volver la red. Home y movimientos se recargan con pull-to-refresh. Un breaker semiabierto deja pasar una petición de prueba y se cierra si funciona | La misma key permite reintentar después |

## Mecanismos y dónde viven

| Mecanismo | Código | Notas |
|---|---|---|
| Orquestación de defensas | `packages/core_network/lib/src/api_client.dart` → `_send`, `get`, `watch`, `post` | Orden: conectividad → breaker → request con reintentos → caché |
| Conectividad | `packages/core_network/lib/src/connectivity.dart` | `connectivity_plus`; emite sólo en transiciones |
| Circuit breaker por servicio | `packages/core_network/lib/src/circuit_breaker.dart` | Servicio = primer segmento después de `/api/` (`serviceOf`). Cuentan como falla los 5xx y los timeouts, no los 4xx de negocio |
| Backoff + jitter | `packages/core_network/lib/src/retry_policy.dart` | `random(0, min(4s, 400ms·2ⁿ))` |
| Caché SWR | `packages/core_network/lib/src/cache_store.dart` (`HiveCacheStore`) | Clave `uid::path?query`; se borra al cerrar sesión (`app/lib/src/app.dart`) |
| Clasificación de errores | `mapDioException` en `api_client.dart` + `packages/core/lib/src/failures.dart` | `isRetryable` decide si se reintenta y si se muestra Reintentar |
| Idempotencia (cliente) | `packages/feature_accounts/lib/src/application/transfer_cubit.dart` | Una key por intención; se conserva entre reintentos y se descarta tras éxito o error de negocio |
| Idempotencia (servidor) | `backend/src/repo/firestore.ts` (`runTransaction` sobre `idempotency/{uid}_{key}`), `backend/src/services/transfers.ts` (`hashTransfer`) | Misma key y mismo payload ⇒ replay. Misma key con otro payload ⇒ 409 |
| Caché del proveedor externo | `backend/src/services/fx.ts` | TTL de 10 min, timeout duro; si el proveedor falla, sirve el último valor con `stale: true` |
| Inyección de fallas | `packages/core_network/lib/src/chaos.dart`, `chaos_interceptor.dart` | En la base del pipeline de Dio: el resto del stack reacciona como ante una falla real |
| Panel de demo | `app/lib/src/demo/chaos_panel.dart` | Muestra en vivo el estado del breaker de cada servicio (se refresca cada 1 s) |

Las degradaciones quedan en Crashlytics como breadcrumbs (`Serving cache for /api/...`, `GET ... failed (attempt n/3)`
con el estado del breaker). Así un crash o un reporte de UX trae consigo el historial de red ([operations.md](operations.md)).

## Guion de demostración (en el dispositivo)

Requisito: sesión iniciada y el home cargado una vez, para que haya caché. El panel se abre con el ícono 🧪
**Escenarios degradados** en la barra superior del home.

1. **Alta latencia.** En el panel, sube *Latencia adicional* a **4000 ms** y vuelve al home. Haz pull-to-refresh.
   → El home y los saldos siguen visibles porque vienen del caché, y el refresco termina unos 4 s después sin bloquear la UI.
   Al abrir una cuenta por primera vez se ven skeletons.
2. **Caída parcial: FX.** Restablece la latencia y marca **fx** como caído. Refresca el home.
   → Sólo la tarjeta de tipos de cambio muestra *"Tipos de cambio no disponibles · Reintentar"*. Saldos, accesos y campañas siguen normales.
3. **Caída parcial: cuentas + circuit breaker.** Marca **accounts** y refresca 1–2 veces.
   → Aparece el banner *"Mostrando datos guardados de HH:mm"* sobre los saldos. En el panel, el breaker de `accounts` pasa a
   **ABIERTO (falla rápida)**: las siguientes lecturas responden al instante desde el caché, sin esperar reintentos.
   Desmarca `accounts`: unos 15 s después pasa a *semiabierto* y con la siguiente petición exitosa queda *cerrado*.
4. **Sin conexión.** Activa **Sin conexión** (o pon el teléfono en modo avión).
   → Banners offline con los datos guardados. Al intentar transferir aparece el mensaje de que no se envió y se puede reintentar sin duplicar.
5. **Recuperación.** Desactiva *Sin conexión* (o quita el modo avión).
   → Saldos y home se recargan solos al volver la conectividad (`OnlineSignal` en el app shell une connectivity_plus y el panel de chaos; `AccountsCubit` y `HomeCubit` refrescan al recibir `true`). Movimientos se refrescan con pull-to-refresh.
6. **Reintento idempotente.** Pon *Tasa de fallas aleatorias* en **50 %** y haz una transferencia.
   → Los 503 inyectados se reintentan con la misma `Idempotency-Key`. Al final hay **un solo** débito y un solo push; puedes comprobarlo
   en el detalle de la cuenta. Ojo: el chaos falla *antes* de llegar al BFF. El caso en que el servidor sí procesó la
   transferencia y la respuesta se perdió lo cubre el replay del servidor. Se comprueba con `curl`, repitiendo el POST con la misma key:
   responde `200` + `Idempotent-Replayed: true`. Hay tests de ambos lados: `api_client_test.dart` y `backend/test`.
7. **Sin caché.** Botón *Borrar caché local* + *Sin conexión*, y vuelve al home.
   → `ErrorView` con *Reintentar*. No se inventan datos.

Todo se deja como estaba con **Restablecer** en el panel.
