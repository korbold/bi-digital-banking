import { errorBody, HttpError } from './http.js';
import * as accounts from './handlers/accounts.js';
import * as devices from './handlers/devices.js';
import * as events from './handlers/events.js';
import * as fx from './handlers/fx.js';
import * as health from './handlers/health.js';
import * as home from './handlers/home.js';
import * as insuranceQuote from './handlers/insurance-quote.js';
import * as me from './handlers/me.js';
import * as movements from './handlers/movements.js';
import * as notificationsTest from './handlers/notifications-test.js';
import * as onboarding from './handlers/onboarding.js';
import * as preferences from './handlers/preferences.js';
import * as status from './handlers/status.js';
import * as transfers from './handlers/transfers.js';

type Handler = (req: Request) => Promise<Response>;
type Module = Partial<Record<'GET' | 'POST' | 'PATCH', Handler>>;

/**
 * Single-function dispatcher. The Vercel Hobby plan caps a deployment at 12
 * functions, so every endpoint is bundled into one function and routed here.
 * Handlers stay one-file-per-endpoint, so splitting back into independent
 * functions (or services) later is a config change, not a rewrite.
 */
const table: Array<[RegExp, Module]> = [
  [/^\/api\/health$/, health],
  [/^\/api\/status$/, status],
  [/^\/api\/me$/, me],
  [/^\/api\/me\/preferences$/, preferences],
  [/^\/api\/onboarding$/, onboarding],
  [/^\/api\/accounts$/, accounts],
  [/^\/api\/accounts\/[^/]+\/movements$/, movements],
  [/^\/api\/transfers$/, transfers],
  [/^\/api\/home$/, home],
  [/^\/api\/events$/, events],
  [/^\/api\/devices$/, devices],
  [/^\/api\/notifications\/test$/, notificationsTest],
  [/^\/api\/fx$/, fx],
  [/^\/api\/insurance\/quote$/, insuranceQuote],
];

export function resolve(method: string, pathname: string): Handler | 'method_not_allowed' | null {
  const entry = table.find(([pattern]) => pattern.test(pathname));
  if (!entry) return null;
  return entry[1][method as keyof Module] ?? 'method_not_allowed';
}

function errorResponse(error: HttpError): Response {
  return new Response(JSON.stringify(errorBody(error.code, error.message)), {
    status: error.status,
    headers: { 'content-type': 'application/json' },
  });
}

export async function dispatch(req: Request): Promise<Response> {
  const url = new URL(req.url);
  // Rewritten requests carry the original path in __path (see vercel.json).
  const rewritten = url.searchParams.get('__path');
  if (rewritten !== null) {
    url.pathname = `/api/${rewritten.trim()}`.replace(/\/+$/, '');
    url.searchParams.delete('__path');
    req = new Request(url, req);
  }
  const handler = resolve(req.method, url.pathname);
  if (handler === null) return errorResponse(new HttpError(404, 'not_found', 'Ruta no encontrada'));
  if (handler === 'method_not_allowed') {
    return errorResponse(new HttpError(405, 'method_not_allowed', 'Método no permitido'));
  }
  return handler(req);
}
