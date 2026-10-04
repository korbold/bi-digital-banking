# Contrato BFF (Backend for Frontend)

Base URL: `https://bi-digital-banking.vercel.app` (Vercel Functions, Node 22, TypeScript).
Persistencia: Cloud Firestore vía `firebase-admin`. Identidad: Firebase Auth.

## Convenciones

- Autenticación: `Authorization: Bearer <Firebase ID token>` en todo excepto `/api/health`.
  El BFF verifica el token con `admin.auth().verifyIdToken`; el `uid` sale del token, nunca del body.
- Correlación: el cliente envía `X-Request-Id`; el BFF lo devuelve y lo loguea.
- Errores: `{ "error": { "code": "snake_case", "message": "texto para humanos (es)" } }`
  - 400 `invalid_request` · 401 `unauthorized` · 404 `not_found` · 409 `idempotency_conflict`
  - 422 reglas de negocio: `insufficient_funds`, `same_account`, `invalid_amount`, `onboarding_required`
  - 502/503 dependencia externa caída (`upstream_unavailable`)
- Escrituras con efecto económico exigen `Idempotency-Key` (UUID). Misma clave + mismo uid ⇒ misma respuesta, sin re-ejecutar.
- Montos: número decimal en USD con 2 decimales. Fechas: ISO-8601 UTC.
- El "servicio" para circuit breaker/chaos es el primer segmento tras `/api/` (`accounts`, `home`, `fx`, `transfers`, ...).

## Modelo Firestore

```
customers/{uid}
  name, email, documentId, segment: young|retail|premium|business,
  preferences: { interests: string[] }, onboardingCompleted: bool, createdAt
customers/{uid}/accounts/{accountId}
  type: savings|checking, alias, number (enmascarado ****1234), currency: USD,
  balance, available, createdAt
customers/{uid}/accounts/{accountId}/movements/{movementId}
  date, description, amount (+crédito / -débito), category, balanceAfter, transferId?
customers/{uid}/devices/{fcmToken}      platform, updatedAt
customers/{uid}/events/{eventId}        type, target, at   (comportamiento para personalización)
experiences/{experienceId}              active, priority, segments[], interests[], section (SDUI), startsAt?, endsAt?
idempotency/{uid}_{key}                 status, body, createdAt
```

`experiences` es la palanca de negocio: un analista agrega una campaña (banner, tarjeta, micro-app)
en Firestore y aparece en el home de los segmentos objetivo **sin publicar la app**.

## Endpoints

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/health` | `{ status: "ok", time, version }` sin auth ni Firebase |
| GET | `/api/me` | Perfil. 404 `onboarding_required` si no hay cliente |
| POST | `/api/onboarding` | Alta del cliente (idempotente por uid) |
| PATCH | `/api/me/preferences` | `{ interests: string[] }` |
| GET | `/api/accounts` | `{ items: Account[] }` |
| GET | `/api/accounts/{id}/movements?limit=20&cursor=` | `{ items: Movement[], nextCursor: string\|null }` |
| POST | `/api/transfers` | Transferencia entre cuentas propias. Requiere `Idempotency-Key` |
| GET | `/api/home` | Pantalla SDUI personalizada |
| POST | `/api/events` | `{ type: "action_used"\|"screen_view", target: string }` → 202 |
| POST | `/api/devices` | `{ token, platform: "android"\|"ios" }` → 204 |
| POST | `/api/notifications/test` | Envía push de prueba a los dispositivos del usuario |
| GET | `/api/fx?base=USD&symbols=EUR,COP,PEN` | Proxy a open.er-api.com, cache 10 min, timeout 3 s → `{ base, rates, updatedAt, provider, stale }`. Si el proveedor cae y hay cache: 200 con `stale: true`; sin cache: 503 `upstream_unavailable` |
| POST | `/api/insurance/quote` | Usado por la micro-app de seguros: `{ product: "travel"\|"device"\|"life", coverage: number }` → `{ quoteId, product, coverage, monthlyPremium, currency, validUntil }`. Rangos: travel 1.000–50.000, device 200–3.000, life 10.000–200.000 (fuera de rango: 422 `invalid_amount`) |

### POST /api/onboarding

```json
// request
{ "name": "Danny Barahona", "documentId": "1003821293",
  "profile": { "ageRange": "18-25|26-40|41-60|60+", "monthlyIncome": 1500, "interests": ["travel","tech","savings"] } }
// 201 response = GET /api/me
{ "uid": "...", "name": "...", "email": "...", "segment": "retail",
  "preferences": { "interests": ["travel"] }, "onboardingCompleted": true }
```
Segmentación: `monthlyIncome >= 5000` ⇒ premium; `ageRange == 18-25` ⇒ young; si no ⇒ retail.
Crea 2 cuentas (ahorros y corriente) con ~25 movimientos realistas de los últimos 45 días.

- `documentId` debe ser una **cédula ecuatoriana válida** (10 dígitos, provincia 01–24/30, dígito verificador
  módulo 10). Si no: 400 `invalid_request` "Cédula inválida".
- `interests` válidos: `travel, tech, savings, shopping, food, health, education, investing` (los demás se ignoran).
- Idempotente: si el cliente ya existe responde **200** con el perfil existente (201 sólo al crear).
- `onboarding_required`: `GET /api/me` responde **404**; el resto de endpoints de cliente responde **422**.

### Account / Movement

```json
{ "id": "acc_x", "type": "savings", "alias": "Cuenta de Ahorros", "number": "****4821",
  "currency": "USD", "balance": 2450.75, "available": 2450.75 }
{ "id": "mov_x", "accountId": "acc_x", "date": "2026-10-03T14:22:00Z", "description": "Supermaxi",
  "amount": -54.20, "category": "groceries", "balanceAfter": 2450.75, "transferId": null }
```

### POST /api/transfers

```json
// request (header Idempotency-Key: <uuid>)
{ "fromAccountId": "acc_a", "toAccountId": "acc_b", "amount": 25.5, "description": "Ahorro" }
// 201
{ "transferId": "trf_x", "from": { "id": "acc_a", "balance": 100.0 }, "to": { "id": "acc_b", "balance": 525.5 },
  "createdAt": "..." }
```
Débito y crédito en **una transacción Firestore**. Tras confirmar, push "Transferencia realizada".

- Sin `Idempotency-Key` (8–100 chars): 400. Reintento con la misma clave y el mismo payload: **200** con el mismo
  body y header `Idempotent-Replayed: true` (no se mueve dinero dos veces). Misma clave con otro payload: 409.
- Monto: > 0, máximo 2 decimales, tope $10.000 (si no: 422 `invalid_amount`). Cuenta inexistente: 404 `not_found`.
- La push es best-effort: si FCM falla, la transferencia igual responde 201.

## SDUI — GET /api/home

```json
{
  "schemaVersion": 1,
  "screen": "home",
  "generatedAt": "2026-10-04T15:00:00Z",
  "segment": "retail",
  "theme": { "seed": "#F07F09" },
  "sections": [
    { "id": "greeting", "type": "greeting", "props": { "title": "Buenas tardes, Danny", "subtitle": "Tu resumen de hoy" } },
    { "id": "accounts", "type": "account_summary", "props": {} },
    { "id": "quick", "type": "quick_actions", "props": { "actions": [
        { "id": "transfer", "label": "Transferir", "icon": "swap_horiz", "action": { "type": "navigate", "route": "/transfer" } },
        { "id": "insurance", "label": "Seguros", "icon": "shield", "action": { "type": "open_miniapp", "miniappId": "insurance" } } ] } },
    { "id": "insight", "type": "spending_insight", "props": { "title": "Este mes", "body": "Gastaste $320.40 en supermercado, 12% menos que el mes pasado", "category": "groceries" } },
    { "id": "promo_travel", "type": "promo_banner", "minAppVersion": 1,
      "props": { "title": "Viaja sin comisiones", "body": "...", "background": "#0B57D0",
                 "cta": { "label": "Ver más", "action": { "type": "open_miniapp", "miniappId": "insurance", "params": { "product": "travel" } } } } },
    { "id": "fx", "type": "fx_rates", "props": { "base": "USD", "symbols": ["EUR", "COP", "PEN"] } },
    { "id": "miniapps", "type": "miniapp_grid", "props": { "items": [
        { "id": "insurance", "title": "Seguros", "icon": "shield", "url": "https://bi-digital-banking.vercel.app/miniapps/insurance/" } ] } },
    { "id": "tip", "type": "text_card", "props": { "title": "Consejo", "body": "..." } }
  ]
}
```

Reglas del motor (cliente):
- Tipo de sección desconocido ⇒ se omite (compatibilidad hacia adelante), se reporta a analytics.
- `minAppVersion` > versión SDUI del cliente ⇒ se omite.
- Una sección que falla al renderizar no rompe la pantalla (error boundary por sección).
- `account_summary` y `fx_rates` son componentes nativos que traen sus propios datos (dominios independientes).

Acciones: `navigate {route}` · `open_miniapp {miniappId, params?}` · `open_url {url}`.

Personalización (servidor): saludo por hora local (America/Guayaquil), orden de quick actions por uso
(`events` action_used de 30 días), insight calculado de movimientos reales, experiencias filtradas por
segmento/intereses/vigencia y ordenadas por prioridad.

## Push (FCM)

```json
{ "notification": { "title": "Transferencia realizada", "body": "Enviaste $25.50 a Cuenta Corriente" },
  "data": { "type": "transfer", "route": "/accounts/acc_a" } }
```
`data.route` es un deep link que el cliente resuelve con go_router al tocar la notificación.

## Puente micro-app (WebView ⇄ host)

- Canal JS: `BiBridge.postMessage(JSON.stringify({ id, method, params }))`.
- Host responde con `window.biBridgeResolve(id, result)` / `window.biBridgeReject(id, error)`.
- Métodos permitidos (allowlist): `getContext` → `{ name, segment, locale, theme }`;
  `getAuthToken` → `{ token }` (ID token de corta vida); `track {event, params}`; `close {result?}`;
  `notifyHost {title, body}` (toast nativo).
- Orígenes permitidos: sólo el dominio del BFF. Cualquier otra navegación se bloquea.
