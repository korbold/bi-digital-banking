import { afterEach, describe, expect, it, vi } from 'vitest';
import { GET as getStatus } from '../src/handlers/status.js';
import { setDeps } from '../src/infra/container.js';
import { MemoryBankRepository } from '../src/repo/memory.js';
import { FxService } from '../src/services/fx.js';

function deps(fetchImpl: typeof fetch) {
  setDeps({
    repo: new MemoryBankRepository(),
    notifier: { sendToUser: vi.fn() },
    fx: new FxService({ fetchImpl }),
    verifier: { verify: vi.fn() },
  });
}

describe('GET /api/status', () => {
  afterEach(() => {
    setDeps(null);
    vi.restoreAllMocks();
  });

  it('is public and reports operational when every dependency answers', async () => {
    vi.spyOn(console, 'log').mockImplementation(() => {});
    deps(vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ result: 'success', base_code: 'USD', rates: { EUR: 0.9 }, time_last_update_unix: 1 })),
    ));
    const res = await getStatus(new Request('https://bff.test/api/status'));
    const body = await res.json();
    expect(res.status).toBe(200);
    expect(body.status).toBe('operational');
    expect(body.checks.map((c: { name: string }) => c.name)).toEqual(['firestore', 'fx_provider']);
  });

  it('reports partial outage when the FX provider is down', async () => {
    vi.spyOn(console, 'log').mockImplementation(() => {});
    deps(vi.fn().mockRejectedValue(new Error('ECONNREFUSED')));
    const body = await (await getStatus(new Request('https://bff.test/api/status'))).json();
    expect(body.status).toBe('partial_outage');
    expect(body.checks.find((c: { name: string }) => c.name === 'fx_provider').status).toBe('down');
  });
});
