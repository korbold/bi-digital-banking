# ADR 0006 — Modelo de seguridad

## Problema
Datos financieros: la app es un entorno no confiable (puede ser modificada, rooteada o interceptada).

## Decisión y controles
| Capa | Control |
|---|---|
| Identidad | Firebase Auth (email/contraseña). ID token JWT de 1 h, refresco automático; ante 401 se fuerza refresco una vez |
| BFF | `verifyIdToken` en cada request; el `uid` sale del token, **nunca del body** (evita IDOR) |
| Datos | Reglas de Firestore `deny all` para clientes: sólo el Admin SDK del BFF accede |
| Operaciones de dinero | Validación en servidor (montos, propiedad de cuentas, saldo) dentro de una transacción; idempotencia obligatoria |
| Transporte | HTTPS (TLS 1.2+); certificate pinning documentado como siguiente paso (ver Riesgos) |
| Caché local | Por usuario (`uid::path`) y se borra en logout. Siguiente paso: cifrado con `HiveAesCipher` y clave en Keystore/Keychain |
| Micro-apps | Allowlist de orígenes y de métodos del puente; el token entregado es de corta vida; navegación externa bloqueada |
| Secretos | Service account sólo en variables de entorno de Vercel; nunca en el repo (`.gitignore` + `.env.example`) |
| Observabilidad | Logs sin PII (no se registran montos con nombres ni tokens); `X-Request-Id` para correlación |

## Alternativas descartadas
- Lógica de negocio en el cliente con reglas de Firestore: imposible garantizar atomicidad e integridad de saldos.
- OAuth/OIDC con Keycloak: más adecuado para producción multi-canal, desproporcionado para el alcance; el BFF lo permitiría cambiando sólo el verificador de tokens.

## Pendiente para producción (riesgo aceptado en la prueba)
Root/jailbreak detection, certificate pinning, App Check (Play Integrity / App Attest), biometría para operaciones,
cifrado de caché, MFA en alta de dispositivo, límites transaccionales y monitoreo antifraude.
