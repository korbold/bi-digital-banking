import { HttpError } from '../http.js';

export interface FxRates {
  base: string;
  rates: Record<string, number>;
  updatedAt: string;
  provider: string;
  /** True when served from cache after the provider failed. */
  stale: boolean;
}

interface CacheEntry {
  value: Omit<FxRates, 'stale'>;
  storedAt: number;
}

export interface FxServiceOptions {
  fetchImpl?: typeof fetch;
  apiUrl?: string;
  ttlMs?: number;
  timeoutMs?: number;
  now?: () => number;
}

/**
 * Proxy to a public exchange-rate API (the "external service" of the
 * ecosystem). Protects the app from the provider's latency and outages:
 *   - in-memory TTL cache per base currency (10 min by default)
 *   - hard timeout on the upstream call
 *   - on upstream failure, serves the last cached value flagged `stale`
 *   - with nothing cached, answers 503 upstream_unavailable
 */
export class FxService {
  private readonly cache = new Map<string, CacheEntry>();
  private readonly fetchImpl: typeof fetch;
  private readonly apiUrl: string;
  private readonly ttlMs: number;
  private readonly timeoutMs: number;
  private readonly now: () => number;

  constructor(options: FxServiceOptions = {}) {
    this.fetchImpl = options.fetchImpl ?? fetch;
    this.apiUrl = (options.apiUrl ?? 'https://open.er-api.com/v6/latest').replace(/\/$/, '');
    this.ttlMs = options.ttlMs ?? 10 * 60_000;
    this.timeoutMs = options.timeoutMs ?? 3_000;
    this.now = options.now ?? Date.now;
  }

  /** Age of a still-fresh cached entry, or null when the next call goes upstream. */
  freshCacheAgeMs(base: string): number | null {
    const cached = this.cache.get(base.toUpperCase());
    if (!cached) return null;
    const age = this.now() - cached.storedAt;
    return age < this.ttlMs ? age : null;
  }

  async getRates(base: string, symbols?: string[]): Promise<FxRates> {
    const key = base.toUpperCase();
    if (!/^[A-Z]{3}$/.test(key)) throw new HttpError(400, 'invalid_request', 'Moneda base inválida');

    const cached = this.cache.get(key);
    if (cached && this.now() - cached.storedAt < this.ttlMs) return this.shape(cached.value, symbols, false);

    try {
      const fresh = await this.fetchUpstream(key);
      this.cache.set(key, { value: fresh, storedAt: this.now() });
      return this.shape(fresh, symbols, false);
    } catch (error) {
      if (cached) return this.shape(cached.value, symbols, true);
      throw new HttpError(503, 'upstream_unavailable', `Servicio de tipos de cambio no disponible: ${String(error)}`);
    }
  }

  private async fetchUpstream(base: string): Promise<Omit<FxRates, 'stale'>> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const res = await this.fetchImpl(`${this.apiUrl}/${base}`, { signal: controller.signal });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const body = (await res.json()) as { result?: string; rates?: Record<string, number>; time_last_update_utc?: string };
      if (body.result !== 'success' || !body.rates) throw new Error('respuesta inválida');
      return {
        base,
        rates: body.rates,
        updatedAt: body.time_last_update_utc ? new Date(body.time_last_update_utc).toISOString() : new Date(this.now()).toISOString(),
        provider: 'open.er-api.com',
      };
    } finally {
      clearTimeout(timer);
    }
  }

  private shape(value: Omit<FxRates, 'stale'>, symbols: string[] | undefined, stale: boolean): FxRates {
    const wanted = symbols?.map((s) => s.toUpperCase()).filter((s) => /^[A-Z]{3}$/.test(s));
    const rates =
      wanted && wanted.length > 0
        ? Object.fromEntries(wanted.filter((s) => s in value.rates).map((s) => [s, value.rates[s]!]))
        : value.rates;
    return { ...value, rates, stale };
  }
}
