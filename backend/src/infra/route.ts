import { HttpError, errorBody, json } from '../http.js';
import { getDeps, type Deps } from './container.js';

export interface Context {
  req: Request;
  url: URL;
  requestId: string;
  uid: string;
  email: string | null;
  deps: Deps;
  log: (entry: Record<string, unknown>) => void;
}

type Handler = (ctx: Context) => Promise<Response>;

interface RouteOptions {
  /** Route template for logs, e.g. "GET /api/accounts/:id/movements". */
  name: string;
  /** Defaults to true. */
  auth?: boolean;
}

function newRequestId(): string {
  return crypto.randomUUID().replaceAll('-', '').slice(0, 16);
}

function log(entry: Record<string, unknown>): void {
  console.log(JSON.stringify({ time: new Date().toISOString(), ...entry }));
}

/**
 * Wraps a handler with the cross-cutting concerns every endpoint shares:
 * request id propagation, Firebase ID token verification, uniform error
 * envelope and one structured log line per request.
 */
export function route(options: RouteOptions, handler: Handler) {
  return async (req: Request): Promise<Response> => {
    const started = Date.now();
    const requestId = req.headers.get('x-request-id')?.slice(0, 64) || newRequestId();
    let uid: string | null = null;
    let response: Response;

    try {
      let email: string | null = null;
      if (options.auth !== false) {
        const header = req.headers.get('authorization') ?? '';
        const token = header.startsWith('Bearer ') ? header.slice(7) : null;
        if (!token) throw new HttpError(401, 'unauthorized', 'Falta el token de sesión');
        try {
          ({ uid, email } = await getDeps().verifier.verify(token));
        } catch {
          throw new HttpError(401, 'unauthorized', 'Sesión inválida o expirada');
        }
      }
      const reqLog = (entry: Record<string, unknown>) => log({ requestId, route: options.name, uid, ...entry });
      response = await handler({
        req,
        url: new URL(req.url),
        requestId,
        uid: uid ?? '',
        email,
        // Lazy so unauthenticated endpoints (health) work without Firebase credentials.
        get deps() {
          return getDeps();
        },
        log: reqLog,
      });
    } catch (error) {
      if (error instanceof HttpError) {
        response = json(errorBody(error.code, error.message), error.status);
      } else {
        log({ level: 'error', requestId, route: options.name, uid, error: String(error), stack: (error as Error)?.stack });
        response = json(errorBody('internal_error', 'Ocurrió un error inesperado'), 500);
      }
    }

    response.headers.set('X-Request-Id', requestId);
    log({
      level: response.status >= 500 ? 'error' : 'info',
      requestId,
      route: options.name,
      uid,
      status: response.status,
      latencyMs: Date.now() - started,
    });
    return response;
  };
}

/** Loads the caller's customer or fails with onboarding_required. */
export async function requireCustomer(ctx: Context, status: 404 | 422 = 422) {
  const customer = await ctx.deps.repo.getCustomer(ctx.uid);
  if (!customer) throw new HttpError(status, 'onboarding_required', 'Completa tu registro para continuar');
  return customer;
}

export function publicBaseUrl(ctx: Context): string {
  return process.env.PUBLIC_BASE_URL || ctx.url.origin;
}
