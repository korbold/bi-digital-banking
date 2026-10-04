// HTTP primitives: error envelope, JSON responses, request validation helpers.

export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'HttpError';
  }
}

export const badRequest = (message: string) => new HttpError(400, 'invalid_request', message);
export const notFound = (message = 'Recurso no encontrado') => new HttpError(404, 'not_found', message);
export const unprocessable = (code: string, message: string) => new HttpError(422, code, message);

export function json(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', ...headers },
  });
}

export function empty(status = 204, headers: Record<string, string> = {}): Response {
  return new Response(null, { status, headers });
}

export function errorBody(code: string, message: string) {
  return { error: { code, message } };
}

export async function readJson(req: Request): Promise<Record<string, unknown>> {
  try {
    const body: unknown = await req.json();
    if (body === null || typeof body !== 'object' || Array.isArray(body)) {
      throw badRequest('El cuerpo debe ser un objeto JSON');
    }
    return body as Record<string, unknown>;
  } catch (e) {
    if (e instanceof HttpError) throw e;
    throw badRequest('JSON inválido');
  }
}

export function requireString(body: Record<string, unknown>, field: string, opts: { min?: number; max?: number } = {}): string {
  const value = body[field];
  if (typeof value !== 'string') throw badRequest(`"${field}" es obligatorio`);
  const trimmed = value.trim();
  const { min = 1, max = 200 } = opts;
  if (trimmed.length < min || trimmed.length > max) {
    throw badRequest(`"${field}" debe tener entre ${min} y ${max} caracteres`);
  }
  return trimmed;
}

export function requireNumber(body: Record<string, unknown>, field: string): number {
  const value = body[field];
  if (typeof value !== 'number' || !Number.isFinite(value)) throw badRequest(`"${field}" debe ser numérico`);
  return value;
}

export function oneOf<T extends string>(value: unknown, allowed: readonly T[], field: string): T {
  if (typeof value !== 'string' || !(allowed as readonly string[]).includes(value)) {
    throw badRequest(`"${field}" debe ser uno de: ${allowed.join(', ')}`);
  }
  return value as T;
}
