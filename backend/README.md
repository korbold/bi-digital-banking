# BFF — Backend for Frontend

API de la banca digital sobre **Vercel Functions (Node 22, TypeScript)** + **Cloud Firestore** vía `firebase-admin`.
Identidad con **Firebase Auth** (el cliente manda su ID token). También sirve la micro-app de seguros
como contenido estático (`public/miniapps/insurance/`).

Contrato completo: [`../docs/api-contract.md`](../docs/api-contract.md).

## Estructura

```
backend/
├── api/                    # Handlers finos (una función por endpoint, Web Request/Response)
├── src/
│   ├── domain/             # Reglas puras, sin I/O: segmentación, seed, personalización (SDUI), seguros
│   ├── services/           # Casos de uso: onboarding, transferencias, FX, push
│   ├── repo/               # Puerto BankRepository + adaptadores Firestore e in-memory
│   └── infra/              # firebase-admin, composition root, wrapper de rutas (auth, errores, logs)
├── public/miniapps/insurance/  # Micro-app de socio (HTML/CSS/JS, puente BiBridge)
├── scripts/seed-experiences.ts # Carga campañas en `experiences/` (contenido sin release)
├── firestore.rules         # deny-all para clientes: todo pasa por el BFF
└── test/                   # vitest
```

Decisiones clave:

- **Dominio puro + puerto de repositorio.** Las reglas (personalización, transferencias) se prueban con un
  repositorio in-memory que respeta la misma semántica transaccional que Firestore.
- **Transferencias**: lectura-validación-escritura en una sola transacción Firestore + registro de idempotencia
  `idempotency/{uid}_{key}`. Un reintento de la app nunca mueve dinero dos veces.
- **FX**: proxy con cache TTL, timeout y respuesta `stale` si el proveedor cae: la app no depende de la
  disponibilidad de un tercero.
- **Observabilidad**: cada request emite una línea JSON `{requestId, route, uid, status, latencyMs}` (visible en
  Vercel Logs / Log Drains). El `X-Request-Id` lo genera la app y se devuelve, para correlacionar app ⇄ backend.

## Variables de entorno

| Variable | Obligatoria | Descripción |
|---|---|---|
| `FIREBASE_SERVICE_ACCOUNT` | Sí | JSON de la cuenta de servicio en **base64** (`base64 -i sa.json \| tr -d '\n'`). Consola Firebase → Configuración → Cuentas de servicio → Generar clave privada. **Nunca** commitear. |
| `PUBLIC_BASE_URL` | No | URL pública usada en las URLs de micro-apps del SDUI. Default: origin de la request. |
| `FX_API_URL` | No | Default `https://open.er-api.com/v6/latest`. |

Ver `.env.example`.

## Desarrollo local

```bash
cd backend
npm install
cp .env.example .env.local   # completar FIREBASE_SERVICE_ACCOUNT
npx vercel dev               # http://localhost:3000
curl localhost:3000/api/health
```

Para llamar endpoints autenticados se necesita un ID token real de Firebase Auth (por ejemplo, el que loguea la
app en modo debug).

## Pruebas

```bash
npm test          # vitest: dominio, servicios y handlers con dependencias in-memory
npm run typecheck # tsc --noEmit
```

## Despliegue

1. `npx vercel link` (proyecto `bi-digital-banking`, Root Directory = `backend`).
2. `npx vercel env add FIREBASE_SERVICE_ACCOUNT production` (pegar el base64) y `PUBLIC_BASE_URL`.
3. `npx vercel deploy --prod`.
4. Publicar reglas de Firestore: `firebase deploy --only firestore:rules` (o pegar `firestore.rules` en la consola).
5. Opcional: `FIREBASE_SERVICE_ACCOUNT=... npm run seed:experiences` para cargar campañas de ejemplo.

Trunk-based: cada push a `main` despliega a producción; cada PR/branch corto obtiene un Preview URL.

## Micro-app de seguros

`/miniapps/insurance/` es una app web independiente (otro "equipo"/socio). Habla con la app anfitriona solo a
través del puente `BiBridge` (`getContext`, `getAuthToken`, `track`, `notifyHost`, `close`) y cotiza contra
`POST /api/insurance/quote` con el token que le entrega el host. Abierta en un navegador normal muestra un modo demo
con estimación referencial.
