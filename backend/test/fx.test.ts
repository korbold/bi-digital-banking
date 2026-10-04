import { describe, expect, it, vi } from 'vitest';
import { FxService } from '../src/services/fx.js';

const okResponse = (rates: Record<string, number>) =>
  new Response(JSON.stringify({ result: 'success', rates, time_last_update_utc: 'Sat, 04 Oct 2026 00:02:31 +0000' }), {
    status: 200,
  });

describe('FxService', () => {
  it('caches per base currency within the TTL', async () => {
    let now = 0;
    const fetchImpl = vi.fn().mockImplementation(async () => okResponse({ EUR: 0.9, COP: 4000 }));
    const fx = new FxService({ fetchImpl, ttlMs: 1000, now: () => now });

    await fx.getRates('USD');
    now = 999;
    const cached = await fx.getRates('usd', ['EUR']);
    expect(fetchImpl).toHaveBeenCalledOnce();
    expect(cached.rates).toEqual({ EUR: 0.9 });
    expect(cached.stale).toBe(false);

    now = 1000;
    await fx.getRates('USD');
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });

  it('serves stale cache when the provider fails after TTL', async () => {
    let now = 0;
    const fetchImpl = vi
      .fn()
      .mockResolvedValueOnce(okResponse({ EUR: 0.9 }))
      .mockResolvedValueOnce(new Response('boom', { status: 502 }));
    const fx = new FxService({ fetchImpl, ttlMs: 10, now: () => now });

    await fx.getRates('USD');
    now = 50;
    const result = await fx.getRates('USD');
    expect(result.stale).toBe(true);
    expect(result.rates.EUR).toBe(0.9);
  });

  it('fails with 503 upstream_unavailable when nothing is cached', async () => {
    const fx = new FxService({ fetchImpl: vi.fn().mockRejectedValue(new Error('ECONNRESET')) });
    await expect(fx.getRates('USD')).rejects.toMatchObject({ status: 503, code: 'upstream_unavailable' });
  });

  it('aborts slow upstream calls after the timeout', async () => {
    const fetchImpl = vi.fn().mockImplementation(
      (_url: string, init: RequestInit) =>
        new Promise((_resolve, reject) => {
          init.signal?.addEventListener('abort', () => reject(new Error('aborted')));
        }),
    );
    const fx = new FxService({ fetchImpl: fetchImpl as unknown as typeof fetch, timeoutMs: 20 });
    await expect(fx.getRates('USD')).rejects.toMatchObject({ code: 'upstream_unavailable' });
  });

  it('rejects invalid base currency', async () => {
    const fx = new FxService({ fetchImpl: vi.fn() });
    await expect(fx.getRates('US')).rejects.toMatchObject({ status: 400 });
  });
});
