# BI Digital — plataforma de banca digital modular (Flutter)

App Flutter de banca digital **sin atención física**. Tiene onboarding, cuentas y movimientos, transferencias, un home personalizado que arma el servidor (Server-Driven UI) y micro-apps de terceros dentro del mismo ecosistema. El backend es real: un BFF en Vercel sobre Firestore, con Firebase Auth y FCM. La app sigue funcionando sin conexión, con latencia alta o con servicios caídos, y ese comportamiento se puede **demostrar en vivo** desde un panel de fallas.

| Recurso | URL |
|---|---|
| 🎬 Video de demostración | [Google Drive](https://drive.google.com/file/d/1bjwkmAwQ2raJ9nT3NgtUM7Q2GiB-J6rr/view?usp=sharing) |
| BFF (producción) + página de estado | https://bi-digital-banking.vercel.app |
| Health check | https://bi-digital-banking.vercel.app/api/health |
| Micro-app de seguros | https://bi-digital-banking.vercel.app/miniapps/insurance/ |
| CI | [GitHub Actions](../../actions) |

## Alcance mínimo → dónde vive

| Requisito | Implementación |
|---|---|
| Onboarding y autenticación | `packages/feature_auth`: Firebase Auth email/contraseña, `SessionCubit`, onboarding en 2 pasos con validación de cédula (módulo 10). Alta en el BFF: `POST /api/onboarding` |
| Cuentas, saldos y movimientos | `packages/feature_accounts`: resumen, detalle con paginación por cursor y transferencias idempotentes entre cuentas propias y a terceros por número de cuenta (con verificación del titular). BFF: `/api/accounts`, `/api/accounts/{id}/movements`, `/api/transfers` (transacción Firestore) |
| Personalización dinámica | `packages/sdui` + `packages/feature_home`. El BFF compone el home (`GET /api/home`) según segmento, intereses, hora local, uso real y gasto del mes, más campañas en la colección `experiences`. Remote Config agrega kill switches |
| Servicio / micro-app externo | Tipos de cambio reales (`/api/fx` → open.er-api.com) y micro-app web de seguros en WebView con puente JS restringido (`packages/feature_miniapps`) |
| Notificaciones push | `packages/feature_notifications` (FCM + notificaciones locales + deep links). El BFF envía push tras cada transferencia y en `POST /api/notifications/test` |
| Monitoreo en producción | [docs/operations.md](docs/operations.md) |
| Conectividad limitada / latencia / caída parcial | [docs/resilience.md](docs/resilience.md) y el panel **Escenarios degradados** de la app |
| Pruebas unitarias, de widgets y E2E | `packages/*/test`, `backend/test`, `app/integration_test/critical_flow_test.dart` |
| Uso de IA | [docs/ai-usage.md](docs/ai-usage.md) |
| Decisiones de arquitectura | [docs/adr/](docs/adr/README.md) (9 ADRs) y [docs/architecture.md](docs/architecture.md) |
| Despliegue y operación | [docs/deployment.md](docs/deployment.md), [docs/operations.md](docs/operations.md) |

## Mapa del repositorio

```
app/                      App shell: composition root (get_it), go_router, Firebase, panel de chaos
  integration_test/       E2E crítico (registro → onboarding → home → transferencia)
packages/
  core/                   Result, AppFailure, contratos de logging/analytics/performance
  core_network/           ApiClient resiliente: circuit breaker, retries con jitter, caché SWR, chaos
  design_system/          Tokens, tema M3 y componentes accesibles (StatusBanner, ErrorView, MoneyText)
  sdui/                   Motor de Server-Driven UI (modelos, registro, renderer con error boundary)
  feature_auth/           Login, registro, onboarding, sesión
  feature_accounts/       Cuentas, movimientos, transferencias
  feature_home/           Home SDUI + sección de tipos de cambio
  feature_miniapps/       Host de micro-apps (WebView + bridge)
  feature_notifications/  Push FCM
backend/                  BFF TypeScript (Vercel Functions) + micro-app estática
docs/                     Contrato API, arquitectura, ADRs, resiliencia, despliegue, operación, IA
```

## Quickstart

### Requisitos

- Flutter **3.41.6** / Dart **3.11** (opcional: `fvm use 3.41.6`)
- Node **22** (el BFF y sus tests)
- `dart pub global activate melos` (opcional, para scripts)
- Firebase CLI y Vercel CLI (sólo para desplegar)
- Un dispositivo Android (API 23+) o un emulador

### App

```bash
flutter pub get                      # en la raíz: pub workspaces resuelve todos los paquetes
cd app
flutter run                          # usa el BFF de producción por defecto
# apuntar a otro BFF:
flutter run --dart-define=BFF_BASE_URL=http://10.0.2.2:3000 --dart-define=ENABLE_CHAOS_PANEL=true
```

`app/lib/firebase_options.dart` y `app/android/app/google-services.json` se generan con
`flutterfire configure --project=<proyecto>`. Contienen configuración pública del cliente, no secretos.

**Credenciales de demo:** regístrate desde la app con cualquier correo. En el onboarding la cédula debe ser
**válida** (el BFF la verifica), por ejemplo `1003821293`. Un ingreso ≥ 5000 crea un cliente *premium*, el rango 18-25 uno *young* y el resto *retail*; cada segmento ve un home distinto.

### Tests

```bash
melos run test                       # unit + widget en todos los paquetes
# sin melos:
for p in packages/*; do (cd $p && flutter test); done

cd backend && npm ci && npm test     # vitest (servicios, router, personalización, idempotencia)
npx tsc --noEmit                     # typecheck del BFF

cd app && flutter test integration_test -d <deviceId>   # E2E contra el backend real
```

### Backend local

```bash
cd backend
cp .env.example .env                 # FIREBASE_SERVICE_ACCOUNT = JSON de la cuenta de servicio en base64
npm ci
vercel dev                           # http://localhost:3000/api/health
```

Más detalle en [backend/README.md](backend/README.md).

## Cómo colaborar

- **Trunk Based Development** ([ADR 0009](docs/adr/0009-trunk-based-development.md)): `main` siempre desplegable. Se hacen commits pequeños o ramas de menos de 1 día con PR. Lo que está incompleto se oculta detrás de un flag de Remote Config, no en una rama.
- **Conventional Commits** con el dominio como scope: `feat(accounts): ...`, `fix(bff): ...`, `docs(adr): ...`.
- **Gate de CI** (`.github/workflows/ci.yml`) en cada push y PR: formato, `flutter analyze` (very_good_analysis), tests con cobertura, typecheck y tests del BFF, y build del APK. Si un commit rompe `main`, primero se revierte y después se investiga.
- **Ownership:** cada `packages/feature_*` puede tener su equipo en `.github/CODEOWNERS`.

### Agregar un dominio nuevo

1. `flutter create --template=package packages/feature_x`, con `resolution: workspace` en su `pubspec.yaml`. Agrégalo a `workspace:` en el `pubspec.yaml` raíz.
2. El paquete sólo depende de `core`, `core_network`, `design_system` y, si hace falta, de `sdui`. **Nunca de otro `feature_*`**, ni de go_router ni de get_it.
3. Expón páginas y widgets que reciban dependencias por constructor y navegación por callbacks.
4. Conéctalo en `app/lib/src/di.dart` (repositorios) y en `app/lib/src/router.dart` (rutas).

### Agregar un tipo de sección SDUI

1. Implementa el widget en el dominio dueño de los datos (o en `sdui/lib/src/defaults.dart` si es genérico).
2. Regístralo en `buildSduiRegistry()` (`app/lib/src/pages/home_shell.dart`) con `registry.register('mi_tipo', builder)`.
3. Emítelo desde el BFF (`backend/src/domain/personalization.ts`) o como campaña en `experiences`. Si las versiones viejas de la app no lo soportan, usa `minAppVersion`: lo omiten sin romperse.
