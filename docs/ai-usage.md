# Uso de herramientas de IA en el desarrollo

La prueba pide documentar cómo se usó la IA y su impacto. Este es un registro honesto.

## Herramienta y forma de trabajo

- **Claude Code** (modelo Claude Opus) en la terminal, como *pair programmer* y agente: escribía código, ejecutaba
  `flutter analyze`, `flutter test`, `npm test` y `curl`, y hacía commits pequeños.
- **Contract-first:** antes de escribir lógica se fijaron los contratos compartidos: `core` (Result y fallas), `core_network`
  (ApiClient), `design_system` y **[api-contract.md](api-contract.md)** (endpoints, modelo Firestore, esquema SDUI, puente de micro-apps).
- Con los contratos fijos, el trabajo se repartió en **3 sub-agentes en paralelo** sobre el mismo repo, cada uno limitado a sus carpetas:
  1. BFF + micro-app de seguros (`backend/`);
  2. `feature_auth` + `feature_accounts`;
  3. `sdui` + `feature_home` + `feature_miniapps` + `feature_notifications`.

  Mientras tanto, el agente principal construía el app shell (DI, router, observabilidad, panel de chaos), el CI y los ADRs, y después integró los
  paquetes usando la API pública que reportó cada sub-agente.

## Rol humano (Danny)

- **Decisiones:** Firebase en lugar de NestJS + Postgres por tiempo y por la necesidad de push. Vercel en lugar del VPS propio en Vultr, para tener HTTPS público
  inmediato sin operar servidor. Recortes de alcance: transferencias sólo entre cuentas propias, sin cola offline para dinero, iOS fuera de la demo.
- **Configuración de plataformas** que la IA no puede ni debe hacer: crear el proyecto Firebase, habilitar Auth y Firestore, generar la
  cuenta de servicio (que nunca pasó por el chat: se cargó directo a Vercel desde el archivo).
- **Revisión** de cada módulo y prueba en un **dispositivo Android físico**.
- Debe poder explicar y modificar cualquier parte en la demo. Por eso se priorizó código pequeño y explícito (por ejemplo, reintentos y
  breaker escritos a mano en lugar de una librería opaca) y documentación con punteros a archivos.

## Impacto

| Área | Impacto observado |
|---|---|
| **Productividad** | Una plataforma de 9 paquetes Flutter + BFF + micro-app + CI + documentación quedó en ~1,5 días de calendario. Estimación propia: unas 2 semanas de trabajo individual sin IA. El paralelismo de los sub-agentes fue lo que más aportó, y fue posible gracias al contrato previo |
| **Calidad** | Los tests se escribieron junto con el código, no al final: **97 tests** unitarios y de widgets en Flutter y **58** en el BFF (vitest), más el E2E en `app/integration_test`. `very_good_analysis` sin warnings en todo el workspace. Errores tipados (`AppFailure`) y `Result` en todas las fronteras |
| **Documentación** | Los 9 ADRs se redactaron a partir de decisiones tomadas en la conversación (con las alternativas descartadas reales). La IA generó diagramas Mermaid a partir del código y de los `pubspec` reales |
| **Pruebas** | La IA propuso casos borde que normalmente se omiten: replay idempotente con payload distinto (409), breaker semiabierto que reabre, secciones SDUI con versión futura, mensajes del puente fuera de la allowlist, cédula inválida |
| **Historial** | 45+ commits convencionales y pequeños sobre `main` (TBD), con el cuerpo del commit explicando el *por qué* |

## Errores de la IA detectados y corregidos

La IA se equivocó, y lo que la frenó fueron las verificaciones (tests, analyzer, smoke tests contra producción):

1. **Límite de 12 funciones de Vercel Hobby.** El BFF se diseñó con una función por endpoint (13) y el primer deploy falló.
   Corrección: router de una sola función con los handlers intactos (`backend/src/router.ts`), más tests del router. La rewrite agregaba
   un espacio al final de la ruta (`/api/health%20`), y eso salió en el smoke test contra producción y se corrigió con su test.
2. **Script de smoke test en zsh:** se asumió la separación de palabras de bash (`set -- $IDS`) y la transferencia de prueba falló con
   un error de validación. El backend estaba bien; el error era del script. Se diagnosticó antes de "arreglar" el backend.
3. **E2E con una key duplicada:** el formulario de registro reutiliza `PasswordField`, así que `Key('password_field')` aparecía dos veces.
   Se detectó revisando los widgets antes de correr el test.
4. **Issues del analyzer** en el código generado: `switch` no exhaustivo sobre `DioExceptionType.transformTimeout`, `const` inválidos,
   tipos `String?` contra `String`. Todos se resolvieron antes de cada commit; el CI hace cumplir lo mismo.

## Riesgos y salvaguardas

- **Secretos:** la IA nunca leyó ni imprimió la clave de la cuenta de servicio. `.gitignore` y `.env.example` evitan commitearla.
- **Contratos y tests como barandas:** el código generado tiene que compilar contra interfaces fijas y pasar tests. Eso sirve más que la revisión visual.
- **Alucinaciones de API:** cada firma que usó el integrador se verificó con `grep` sobre el código real antes de conectarla.
- **Propiedad del conocimiento:** todo lo entregado está documentado con punteros a archivos para poder explicarlo y modificarlo en vivo.
  Si una parte no se puede explicar, no debería estar.
