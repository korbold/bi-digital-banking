# ADR 0004 — Personalización con Server-Driven UI + feature flags

## Problema
"La experiencia debe adaptarse dinámicamente al contexto, perfil, comportamiento o preferencias" y
"permitir incorporar nuevas experiencias, contenidos o componentes visuales sin requerir una nueva publicación".
Las tiendas tardan horas o días en aprobar; la mitad de los usuarios no actualiza en semanas.

## Alternativas evaluadas
| Opción | A favor | En contra |
|---|---|---|
| Sólo Remote Config (flags + strings) | Simple, nativo Firebase | Sólo prende/apaga lo que ya existe; no compone pantallas; segmentación limitada |
| **SDUI: el BFF devuelve la composición del home (secciones tipadas + props + acciones)** | Orden, contenido y campañas por segmento sin release; la lógica de personalización vive en servidor | Hay que versionar el esquema; sólo se puede componer con widgets que el cliente ya conoce |
| Code push (Shorebird) | Cambia código Dart sin tienda | Restricciones de políticas de tienda para cambios de funcionalidad; riesgo operativo en banca |
| WebViews para todo el contenido dinámico | Máxima flexibilidad | UX inconsistente, accesibilidad y rendimiento peores |

## Decisión
**SDUI para composición + Remote Config para capacidades:**
- `GET /api/home` devuelve `sections[]` con `type`, `props`, `minAppVersion` y `action`.
- El cliente tiene un `SduiRegistry` (tipo → builder). Tipos desconocidos o con `minAppVersion` mayor se omiten (forward-compatible).
- Cada sección se renderiza dentro de un *error boundary*: una sección rota no tumba la pantalla.
- Secciones "nativas" (`account_summary`, `fx_rates`) cargan sus propios datos ⇒ fallan de forma independiente.
- Campañas nuevas = documento en la colección `experiences` (segmentos, intereses, vigencia, prioridad) ⇒ aparecen sin release.
- Remote Config: kill switches (`transfers_enabled`, `miniapps_enabled`) y mensaje de mantenimiento.

Señales de personalización usadas: segmento (onboarding), intereses declarados, hora local, uso real de accesos
rápidos (eventos), gasto real del mes por categoría.

## Trade-offs
- (+) Marketing/producto publican experiencias en minutos y por segmento.
- (+) Un error en una campaña se corrige en servidor, no con un hotfix en tiendas.
- (−) Un componente visual realmente nuevo sí requiere release (se mitiga con micro-apps, ADR 0007).
- (−) El esquema es un contrato público: cambios incompatibles requieren `schemaVersion` nuevo.

## Impacto a largo plazo
El mismo motor sirve para otras pantallas (ofertas, post-transferencia) y para experimentos A/B (el BFF decide
variante y la reporta a analytics). Siguiente paso natural: un backoffice para editar `experiences` con preview.
