# Operación y monitoreo en producción

Objetivo: enterarse **antes que el cliente** de un problema operativo (errores, latencia, caídas) o de experiencia (pantallas
degradadas, abandono en el onboarding) y poder llegar a la causa en minutos.

## Qué está instrumentado hoy

### App

Los features dependen de los contratos de `packages/core` (`AppLogger`, `AnalyticsTracker`, `PerformanceTracer`), y el shell los
conecta a Firebase en `app/lib/src/observability/firebase_observability.dart`.

| Señal | Implementación | Para qué sirve |
|---|---|---|
| Crashes fatales | `FlutterError.onError` + `PlatformDispatcher.onError` → Crashlytics (`app/lib/main.dart`) | Crash-free users, stack traces |
| Errores no fatales | `AppLogger.error` → `recordError`. Ejemplos: secciones SDUI que fallan al renderizar, respuestas mal formadas | Detectar UX rota que no crashea |
| Breadcrumbs | `info`/`warning` → `Crashlytics.log`: reintentos (`GET /api/x failed (attempt n/3)` con el estado del breaker), `Serving cache for /api/x` | Cada crash trae el historial de red y degradación previo |
| Eventos de producto (Analytics) | `login_success/failure`, `sign_up`, `onboarding_step`, `onboarding_completed`, `transfer_success/failure`, `sign_out`, `sdui_section_skipped`, `miniapp_<evento>`, screen views (`FirebaseAnalyticsObserver` en go_router), user property `segment` | Funnels, adopción, segmentación |
| Comportamiento para personalización | `action_used` → `POST /api/events` (Firestore) | Ordena los accesos rápidos del home |
| Traces de Performance | `ApiClient` envuelve cada request en `api_<servicio>` (`api_accounts`, `api_home`, `api_fx`...) con atributos `method` y `outcome` | Latencia p50/p95 por servicio, vista desde el dispositivo |
| Correlación | Cada request lleva `X-Request-Id` | Unir un reporte del cliente con el log del BFF |

### BFF

`backend/src/infra/route.ts` escribe **una línea JSON por request** en los logs de Vercel:
`{time, level, requestId, route, uid, status, latencyMs}`. Los errores 5xx también incluyen `error` y `stack`. El BFF devuelve
`X-Request-Id` en todas las respuestas, y las respuestas de error usan el formato `{error:{code,message}}`, con lo que se pueden agregar por `code`.

## SLIs / SLOs propuestos

| SLI | Fuente | SLO | Ventana |
|---|---|---|---|
| Usuarios sin crash | Crashlytics | ≥ 99.8 % | 7 días |
| Latencia p95 de `api_accounts` y `api_home` (dispositivo) | Performance | ≤ 1.5 s | 1 día |
| Latencia p95 de `/api/transfers` (servidor) | logs del BFF (`latencyMs`) | ≤ 800 ms | 1 día |
| Tasa de 5xx del BFF | logs del BFF | ≤ 0.5 % de requests | 1 h |
| Éxito de transferencias | `transfer_success / (success + failure)`, sin contar errores de negocio | ≥ 99.5 % | 1 día |
| Sesiones servidas desde caché | breadcrumbs → *propuesta*: evento `served_from_cache` | ≤ 2 % fuera de ventanas de mantenimiento | 1 h |
| Entrega de push | respuestas de `sendEachForMulticast` (éxitos/fallos, tokens inválidos que se limpian) | ≥ 98 % | 1 día |
| Onboarding completado | `onboarding_completed / sign_up` | línea base + alerta ante una caída del 20 % | 1 día |

## Alertas

| Condición | Severidad | Canal |
|---|---|---|
| Crash-free < 99.5 % en una versión nueva | P1, detener el staged rollout | Crashlytics velocity alert → Slack/PagerDuty |
| 5xx del BFF > 2 % durante 5 min | P1 | Log drain de Vercel (Datadog/Axiom) → monitor |
| p95 de `/api/transfers` > 2 s durante 10 min | P2 | monitor sobre `latencyMs` |
| `upstream_unavailable` en `/api/fx` > 50 % durante 15 min | P3, la sección degrada sola | monitor por `code` |
| Pico de `sdui_section_skipped` tras publicar una campaña | P2: campaña con un tipo o versión que la app no soporta | Analytics + BigQuery export |
| Caída del 20 % en `onboarding_completed / sign_up` | P2 de producto | dashboard de funnel |

## Dashboards

1. **Salud técnica:** crash-free por versión, 5xx y latencia p95 por ruta (BFF), traces `api_*` por servicio (app).
2. **Experiencia degradada:** sesiones con caché, breakers abiertos por servicio y fallas de FX y micro-apps.
3. **Producto:** funnel registro → onboarding → primera vista de saldo → primera transferencia; uso de accesos rápidos y campañas por segmento.

## Detectar problemas de experiencia (no sólo errores)

- **Abandono en el onboarding:** `onboarding_step` muestra en qué paso se cae el funnel. Picos de errores de cédula apuntan a un problema de copy o validación.
- **Tiempo hasta el primer saldo:** trace de pantalla desde el login hasta que `AccountsCubit` emite *loaded* (propuesta: un trace `time_to_first_balance`).
- **Contenido roto o invisible:** `sdui_section_skipped` (tipo desconocido o versión) y los no fatales de secciones que fallan.
- **Frustración:** Firebase no tiene detección de *rage taps*. Como aproximación se usan los reintentos manuales repetidos (Reintentar ≥ 3 veces en 1 min), el pull-to-refresh insistente y `transfer_failure` seguido de abandono. Si se necesita más, una herramienta de session replay (por ejemplo Smartlook o UXCam) con enmascaramiento de datos financieros.

## Diagnóstico on-call con `requestId`

1. El cliente o soporte reporta la hora y el uid. En Crashlytics se busca el usuario: los breadcrumbs muestran la ruta que falló, el intento y el estado del breaker.
2. En los logs de Vercel se filtra por `uid` y ventana de tiempo, y luego por `requestId` para ver la línea exacta (`status`, `latencyMs`, `error`, `stack`).
3. Se clasifica: 4xx de negocio (no es incidente), 5xx propio, `upstream_unavailable` o timeout del cliente sin log en el servidor (red o cold start).

Cada falla de red deja un breadcrumb en Crashlytics con el mismo `requestId` que el cliente envía en `X-Request-Id` y que el BFF escribe en su log: se salta del crash al log del servidor sin buscar por tiempo.

## Runbooks

### 1. Pico de 5xx en el BFF
1. Dashboard: ¿una ruta o todas? ¿Coincide con un deploy?
2. Si coincide con un deploy, **instant rollback** en Vercel, que tarda segundos ([deployment.md](deployment.md)).
3. Si son todas las rutas sin deploy reciente, revisar el estado de Firebase o Firestore y las cuotas del plan, y probar `GET /api/health`.
4. Si es una ruta de dinero, apagar `transfers_enabled` en Remote Config y publicar `maintenance_message`.
5. Postmortem con los `requestId` representativos.

### 2. Proveedor de tipos de cambio caído
1. Síntoma: `upstream_unavailable` en `/api/fx`, o respuestas con `stale: true`.
2. Impacto acotado: sólo la tarjeta FX muestra *"Tipos de cambio no disponibles"*. El BFF sirve el último valor durante el TTL.
3. Acción: si se prolonga, quitar la sección `fx_rates` del home desde el BFF o cambiar a otro proveedor con `FX_API_URL` y redeploy.

### 3. Las push no llegan
1. `POST /api/notifications/test` con el usuario afectado: si responde 200 y no llega, el problema está en el dispositivo o en FCM.
2. Revisar `customers/{uid}/devices`: si no hay token, la app no lo registró. Puede faltar el permiso en Android 13+ o haber fallado `POST /api/devices`.
3. Los logs del notifier muestran éxitos y fallos por token. Los tokens `not-registered` o inválidos se borran automáticamente; si todos fallan, revisar la cuenta de servicio y la API de FCM.
4. En el dispositivo: optimización de batería, canal `transactions` silenciado, app detenida a la fuerza (Android no entrega push a apps detenidas).
