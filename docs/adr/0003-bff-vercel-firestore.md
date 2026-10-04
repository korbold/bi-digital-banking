# ADR 0003 — BFF en Vercel Functions sobre Firestore

## Problema
La prueba penaliza datos simulados: se necesita backend real con lógica (transferencias atómicas, segmentación,
personalización, integración externa, envío de push) y el proyecto Firebase está en **plan Spark** (sin Cloud Functions).

## Alternativas evaluadas
| Opción | A favor | En contra |
|---|---|---|
| App → Firestore directo (reglas de seguridad) | Offline nativo, cero backend | Lógica de negocio en el cliente; transferencias y personalización inseguras; acopla la app al esquema de BD |
| Cloud Functions | Integración nativa Firebase | Requiere plan Blaze (tarjeta) |
| NestJS + Postgres (Railway/Fly) | Backend "enterprise" completo | +8 h de trabajo, infraestructura extra a operar |
| **BFF en Vercel Functions (TypeScript) + Firestore vía Admin SDK** | Serverless, gratis, deploy por git; lógica en servidor; la app depende de un contrato HTTP, no de la BD | Cold starts; dos plataformas (Vercel + Firebase) |

## Decisión
**BFF** (Backend for Frontend) en Vercel. El cliente sólo usa Firebase para identidad (Auth), push (FCM),
flags (Remote Config) y telemetría. Los datos de negocio pasan siempre por el BFF, que verifica el ID token.
Las reglas de Firestore niegan todo acceso directo del cliente.

## Trade-offs
- (+) Contrato estable (`docs/api-contract.md`): el backend puede migrar a microservicios/core bancario sin tocar la app.
- (+) La resiliencia (caché, reintentos, circuit breaker) se implementa y demuestra en la app, no queda oculta en el SDK de Firestore.
- (−) Sin offline "gratis" del SDK de Firestore: lo cubre nuestra caché SWR (ADR 0005).
- (−) Cold start ~300-800 ms en la primera llamada; mitigado por el caché y skeletons.

## Impacto a largo plazo
El BFF es el punto natural para un API Gateway / agregador cuando existan varios dominios backend
(core bancario, seguros, inversiones). Cada dominio del app consume "su" ruta (`/api/accounts`, `/api/insurance`),
lo que mapea 1:1 a ownership de equipos backend.
