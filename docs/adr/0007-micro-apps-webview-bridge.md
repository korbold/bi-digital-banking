# ADR 0007 — Micro-apps de terceros vía WebView + puente

## Problema
"Integrar servicios propios o de terceros dentro de un mismo ecosistema" e incorporar experiencias nuevas sin publicar
la app. Un aliado (aseguradora, marketplace) no puede ni debe entregar código Dart para compilar dentro de la app bancaria.

## Alternativas evaluadas
| Opción | A favor | En contra |
|---|---|---|
| Paquete Flutter del tercero dentro del binario | UX nativa | Requiere release por cada cambio del tercero; código ajeno en el binario bancario |
| Redirigir a la web/app del tercero | Cero integración | Rompe la experiencia, pierde contexto y sesión |
| **WebView con puente JS controlado (patrón "mini-programs")** | El tercero despliega a su ritmo; contexto y sesión compartidos de forma controlada | UX web; hay que endurecer el puente |
| Flutter web embebido / Dart dinámico | — | No soportado de forma estable |

## Decisión
`feature_miniapps` hospeda micro-apps web en un `WebView`. Protocolo (ver contrato):
`BiBridge.postMessage({id, method, params})` → host responde `biBridgeResolve/Reject(id, ...)`.
- **Allowlist de métodos**: `getContext`, `getAuthToken`, `track`, `notifyHost`, `close`. Cualquier otro ⇒ rechazado.
- **Allowlist de orígenes**: navegación fuera del dominio permitido se bloquea.
- La lógica del puente está separada del WebView ⇒ se prueba unitariamente.
- Ejemplo real: micro-app de **seguros** desplegada independientemente, que cotiza contra `/api/insurance/quote`.

## Trade-offs
- (+) Nuevos productos de aliados se publican sin release de la app; el catálogo se controla por SDUI (`miniapp_grid`).
- (−) Rendimiento y accesibilidad dependen del tercero ⇒ se exigen guías (contraste, tamaños, semántica).
- (−) Superficie de ataque: mitigada con allowlists, tokens de corta vida y CSP en la micro-app.

## Impacto a largo plazo
Base de un "marketplace" de servicios no financieros. Siguiente paso: tokens específicos por micro-app con
scopes (token exchange) en lugar de compartir el ID token del usuario.
