# Arquitectura

Las decisiones con sus alternativas y trade-offs están en [docs/adr](adr/README.md). Este documento describe
cómo encajan las piezas.

## 1. Contexto

```mermaid
flowchart LR
  user((Cliente))
  subgraph device[Dispositivo Android]
    app[App Flutter<br/>app shell + feature packages]
    web[Micro-app web<br/>WebView]
  end
  subgraph vercel[Vercel]
    bff[BFF<br/>TypeScript, 1 función + router]
    static[/miniapps/insurance<br/>estático/]
  end
  subgraph firebase[Firebase]
    auth[Auth]
    fcm[Cloud Messaging]
    rc[Remote Config]
    obs[Crashlytics · Analytics · Performance]
    fs[(Firestore)]
  end
  fx[open.er-api.com<br/>tipos de cambio]

  user --> app
  app -- email/contraseña --> auth
  app -- HTTPS + ID token --> bff
  app -- flags --> rc
  app -- telemetría --> obs
  fcm -- push --> app
  app <-- BiBridge --> web
  web -- carga --> static
  web -- cotización + token --> bff
  bff -- verifyIdToken --> auth
  bff -- Admin SDK --> fs
  bff -- envío push --> fcm
  bff -- proxy con caché --> fx
```

Principios:
- **La app nunca toca Firestore.** Las reglas son `deny all` y todo pasa por el BFF, que toma el `uid` del token ([ADR 0003](adr/0003-bff-vercel-firestore.md), [ADR 0006](adr/0006-seguridad.md)).
- Firebase se usa para lo que hace mejor: identidad, push, flags y telemetría.
- El contrato HTTP está en [api-contract.md](api-contract.md). El backend puede cambiar (core bancario, microservicios) sin tocar la app.

## 2. Paquetes y dependencias

Grafo tomado de los `pubspec.yaml` reales:

```mermaid
flowchart TD
  app[app<br/>composition root]
  subgraph features[Dominios]
    auth[feature_auth]
    acc[feature_accounts]
    home[feature_home]
    mini[feature_miniapps]
    push[feature_notifications]
  end
  subgraph platform[Plataforma]
    sdui[sdui]
    net[core_network]
    ds[design_system]
    core[core]
  end

  app --> auth & acc & home & mini & push & sdui & net & ds & core
  auth --> core & net & ds
  acc --> core & net & ds
  home --> core & net & ds & sdui
  mini --> core & ds
  push --> core & net
  sdui --> core & ds
  net --> core
```

Regla: **ningún `feature_*` depende de otro.** El único que los conoce a todos es el app shell. Por ejemplo, la sección
`account_summary` de *accounts* aparece en el home de *home* porque el shell la registra en el `SduiRegistry`
(`app/lib/src/pages/home_shell.dart`, `buildSduiRegistry`).

### Capas dentro de un dominio

```mermaid
flowchart LR
  pres[presentation<br/>Pages, widgets] --> appl[application<br/>Cubits + estados]
  appl --> dom[domain<br/>modelos, interfaces de repositorio]
  data[data<br/>ApiXxxRepository] --> dom
  data --> net[core_network.ApiClient]
```

- `domain` no depende de Flutter ni de HTTP: modelos y contratos (`AccountsRepository`).
- `data` implementa los contratos sobre `ApiClient` y devuelve `Result<T>`, nunca lanza excepciones.
- `application` usa Cubits con estados inmutables que modelan explícitamente "datos en caché + error de refresco" ([ADR 0002](adr/0002-gestion-de-estado-cubit.md)).
- `presentation` recibe dependencias por constructor y navega con callbacks ([ADR 0008](adr/0008-navegacion-y-di.md)).

## 3. Flujos principales

### Login y onboarding

```mermaid
sequenceDiagram
  actor U as Cliente
  participant App
  participant Auth as Firebase Auth
  participant BFF
  participant FS as Firestore

  U->>App: email + contraseña
  App->>Auth: signIn / register
  Auth-->>App: AuthUser (stream)
  App->>BFF: GET /api/me (Bearer ID token)
  BFF->>Auth: verifyIdToken
  BFF->>FS: customers/{uid}
  alt cliente no existe
    BFF-->>App: 404 onboarding_required
    App->>App: SessionNeedsOnboarding → /onboarding
    U->>App: nombre, cédula, perfil
    App->>BFF: POST /api/onboarding
    BFF->>BFF: valida cédula, calcula segmento
    BFF->>FS: crea cliente + 2 cuentas + ~25 movimientos
    BFF-->>App: 201 perfil
  else existe
    BFF-->>App: 200 perfil
  end
  App->>App: SessionAuthenticated → /home (redirect de go_router)
```

### Home SDUI: caché primero, luego red

```mermaid
sequenceDiagram
  participant Home as HomeCubit
  participant API as ApiClient.watch
  participant Cache as HiveCacheStore
  participant BFF

  Home->>API: watch('/api/home')
  API->>Cache: read(uid::/api/home)
  Cache-->>API: último home guardado
  API-->>Home: Fetched(source: cache)
  Home-->>Home: renderiza al instante
  API->>BFF: GET /api/home
  alt OK
    BFF-->>API: SduiScreen personalizado
    API->>Cache: write
    API-->>Home: Fetched(source: network)
  else falla
    API-->>Home: Failure → estado stale + banner "Mostrando datos de las HH:mm"
  end
```

### Transferencia idempotente + push

```mermaid
sequenceDiagram
  participant T as TransferCubit
  participant API as ApiClient
  participant BFF
  participant FS as Firestore
  participant FCM

  T->>T: genera Idempotency-Key (1 por intención del usuario)
  T->>API: POST /api/transfers + key
  API->>BFF: intento 1
  BFF--xAPI: 503 / timeout
  API->>BFF: reintento con backoff + jitter (misma key)
  BFF->>FS: runTransaction: lee idempotency/{uid}_{key}
  alt key ya usada con mismo payload
    FS-->>BFF: respuesta guardada
    BFF-->>API: 200 + Idempotent-Replayed: true
  else key nueva
    BFF->>FS: débito + crédito + 2 movimientos + registro de idempotencia (atómico)
    BFF->>FCM: "Transferencia realizada" a customers/{uid}/devices
    BFF-->>API: 201 comprobante
  end
  API-->>T: TransferReceipt → AccountsCubit.applyReceipt
```

Una key reutilizada con otro payload responde 409 `idempotency_conflict`. El servidor compara un hash de la solicitud
(`backend/src/services/transfers.ts`, `hashTransfer`).

### Llamada del puente de una micro-app

```mermaid
sequenceDiagram
  participant W as Micro-app (JS)
  participant P as MiniAppPage (WebView)
  participant B as MiniAppBridge
  participant BFF

  W->>P: BiBridge.postMessage({id, method:"getAuthToken"})
  P->>B: handle(raw)
  B->>B: ¿método en la allowlist?
  B-->>P: token de corta vida
  P->>W: window.biBridgeResolve(id, {token})
  W->>BFF: POST /api/insurance/quote (Bearer token)
  BFF-->>W: prima mensual
  W->>P: BiBridge close({result})
  P-->>P: Navigator.pop(result)
```

Los métodos fuera de la allowlist (`getContext`, `getAuthToken`, `track`, `notifyHost`, `close`) se rechazan, y la navegación
fuera del origen permitido se bloquea ([ADR 0007](adr/0007-micro-apps-webview-bridge.md)).

### Lectura con un servicio caído

```mermaid
sequenceDiagram
  participant C as AccountsCubit
  participant API as ApiClient
  participant CB as CircuitBreaker(accounts)
  participant Cache

  C->>API: watch('/api/accounts')
  API->>CB: allowsRequest?
  alt circuito abierto (≥3 fallas, < 15 s)
    CB-->>API: no
    API->>Cache: read
    Cache-->>API: último dato bueno
    API-->>C: Fetched(source: cache) → banner, sin esperar timeouts
  else cerrado / semiabierto
    API->>API: request + reintentos
  end
```

## 4. Motor SDUI

- **Modelo** (`packages/sdui/lib/src/models.dart`): `SduiScreen` → `sections[]` con `id`, `type`, `properties`, `minAppVersion`,
  y acciones selladas `NavigateAction`, `OpenMiniAppAction`, `OpenUrlAction` (solo https) y `UnknownAction`. El parseo es tolerante:
  una sección mal formada se descarta sin tumbar la pantalla.
- **Registro** (`registry.dart`): `type → builder(context, section, onAction)`. Los genéricos se registran con `registerDefaults`
  (greeting, quick_actions, promo_banner, text_card, spending_insight). Los dominios registran los suyos: `fx_rates` desde home y
  `account_summary` desde accounts, vía el shell.
- **Renderer** (`renderer.dart`): omite tipos desconocidos y secciones con `minAppVersion > kSduiVersion` y lo reporta con
  `onSkipped`, que en el shell se convierte en el evento `sdui_section_skipped`. Cada sección va dentro de un *error boundary*:
  si su builder lanza una excepción, se reporta a Crashlytics y el resto de la pantalla sigue funcionando.
- **Servidor** (`backend/src/domain/personalization.ts`): es una función pura (sin I/O) y por eso está cubierta por tests. Calcula:
  - el saludo según la hora de America/Guayaquil;
  - el orden de los accesos rápidos según los eventos `action_used` de los últimos 30 días;
  - el insight de gasto del mes contra el mes anterior, desde los movimientos reales;
  - hasta 3 experiencias de la colección `experiences`, filtradas por segmento, intereses y vigencia, y ordenadas por prioridad.
- **Nuevas experiencias sin release:** basta con un documento nuevo en `experiences` (`backend/scripts/seed-experiences.ts` muestra el formato).

## 5. Supuestos

- Cliente persona natural en Ecuador: cédula válida y USD como moneda única.
- Transferencias sólo entre cuentas propias del cliente. Las interbancarias quedan fuera de alcance: requieren integración SPI/BCE.
- Los saldos y movimientos iniciales se generan en el onboarding (*seed* determinístico). Desde ahí, todo el flujo es real y persistente.
- Android es la plataforma de la demo. El código no tiene nada específico de Android salvo la configuración de Gradle y del manifest.
- El proyecto Firebase está en plan Spark, sin Cloud Functions. Por eso la lógica de servidor vive en Vercel.

## 6. Riesgos técnicos

| Riesgo | Impacto | Mitigación actual | Siguiente paso |
|---|---|---|---|
| Cold start de la función en Vercel | Primera carga lenta | Caché SWR + skeletons; timeouts de 8 s (conexión) y 12 s (respuesta) | Plan con funciones calientes o contenedor siempre activo |
| Límite de 12 funciones (Hobby) | No se podía desplegar un endpoint por función | Un único `api/index.ts` + `src/router.ts`; los handlers siguen siendo un archivo por endpoint | Volver a separar funciones al pasar a Pro o a microservicios |
| Datos en caché desactualizados | El cliente ve un saldo viejo | Siempre se etiquetan con la hora; nunca se usan para validar una transferencia (lo hace el servidor) | TTL máximo de visualización por tipo de dato |
| Caché local sin cifrar | Saldos legibles en un dispositivo comprometido | Separado por `uid` y borrado al cerrar sesión | `HiveAesCipher` con la clave en Keystore ([ADR 0006](adr/0006-seguridad.md)) |
| Micro-app de terceros | Superficie de ataque, UX inconsistente | Allowlist de métodos y de origen, token de corta vida | Token exchange con scopes por micro-app, CSP |
| Esquema SDUI como contrato público | Un cambio incompatible rompe apps viejas | `minAppVersion`, omisión de tipos desconocidos, error boundary | `schemaVersion` por pantalla + tests de contrato |
| Proveedor de tipos de cambio caído | La sección FX falla | Caché de 10 min en el BFF que responde `stale: true`; la sección falla sola, sin afectar el resto | Segundo proveedor como respaldo |
| Dependencia de un único proyecto Firebase | Sin aislamiento entre entornos | — | Un proyecto por entorno ([deployment.md](deployment.md)) |

## 7. Estrategia de escalamiento

- **Más dominios y equipos:** cada dominio nuevo es un paquete con CODEOWNERS y sus propios tests. Los límites los impone el `pubspec`.
  Si un dominio necesita su propio ciclo de release, se extrae a otro repo sin reescribirlo, porque ya tiene API pública.
- **Backend:** hoy el BFF es un monolito modular. El paso natural es un **API Gateway + microservicios por dominio**
  (`/api/accounts` → core bancario, `/api/insurance` → aliado). La app no cambia porque depende del contrato. El circuit breaker por
  servicio en el cliente ya asume que los dominios fallan de forma independiente.
- **Datos y tráfico:** Firestore escala horizontalmente. Las lecturas calientes (home, FX) se pueden cachear en el edge con
  `Cache-Control` por segmento. FX ya tiene caché en memoria por instancia.
- **Multi-región:** Vercel ya sirve desde el edge. Para latencia y residencia de datos se usaría Firestore multirregión o una réplica por región.
- **Releases seguros:** feature flags de Remote Config con rollout por porcentaje, además de staged rollout en Play
  ([deployment.md](deployment.md)).
- **Personalización:** se escala con un backoffice para editar `experiences` con vista previa por segmento y con experimentos A/B
  (el BFF elige la variante y la reporta a analytics).
