import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { GET as getAccounts } from '../api/accounts/index.js';
import { GET as getHealth } from '../api/health.js';
import { POST as postTransfer } from '../api/transfers.js';
import { setDeps } from '../src/infra/container.js';
import { MemoryBankRepository } from '../src/repo/memory.js';
import { FxService } from '../src/services/fx.js';
import { account, customer } from './fixtures.js';

describe('route wrapper + handlers', () => {
  let repo: MemoryBankRepository;

  beforeEach(async () => {
    vi.spyOn(console, 'log').mockImplementation(() => {});
    repo = new MemoryBankRepository();
    await repo.createCustomer(customer(), [account('acc_a', 100), account('acc_b', 0)], []);
    setDeps({
      repo,
      notifier: { sendToUser: vi.fn().mockResolvedValue({ sent: 0, failed: 0, removedTokens: 0 }) },
      fx: new FxService({ fetchImpl: vi.fn() }),
      verifier: {
        verify: async (token) => {
          if (token !== 'good') throw new Error('bad token');
          return { uid: 'user-1', email: 'danny@example.com' };
        },
      },
    });
  });

  afterEach(() => {
    setDeps(null);
    vi.restoreAllMocks();
  });

  const req = (path: string, init: RequestInit & { token?: string } = {}) =>
    new Request(`https://bff.test${path}`, {
      ...init,
      headers: {
        ...(init.token ? { Authorization: `Bearer ${init.token}` } : {}),
        'X-Request-Id': 'req-123',
        'Content-Type': 'application/json',
        ...(init.headers as Record<string, string> | undefined),
      },
    });

  it('health needs no auth or Firebase', async () => {
    setDeps(null);
    const res = await getHealth(req('/api/health'));
    expect(res.status).toBe(200);
  });

  it('rejects missing and invalid tokens with the error envelope', async () => {
    const missing = await getAccounts(req('/api/accounts'));
    expect(missing.status).toBe(401);
    expect(await missing.json()).toEqual({ error: { code: 'unauthorized', message: expect.any(String) } });

    const invalid = await getAccounts(req('/api/accounts', { token: 'nope' }));
    expect(invalid.status).toBe(401);
  });

  it('echoes X-Request-Id and logs one structured line per request', async () => {
    const res = await getAccounts(req('/api/accounts', { token: 'good' }));
    expect(res.status).toBe(200);
    expect(res.headers.get('X-Request-Id')).toBe('req-123');
    const lines = vi.mocked(console.log).mock.calls.map((c) => JSON.parse(String(c[0])));
    expect(lines.at(-1)).toMatchObject({ requestId: 'req-123', route: 'GET /api/accounts', uid: 'user-1', status: 200 });
    expect(typeof lines.at(-1).latencyMs).toBe('number');
  });

  it('transfer returns 201 then 200 with Idempotent-Replayed on retry', async () => {
    const init = {
      method: 'POST',
      token: 'good',
      headers: { 'Idempotency-Key': 'key-12345678' },
      body: JSON.stringify({ fromAccountId: 'acc_a', toAccountId: 'acc_b', amount: 10, description: 'x' }),
    };
    const first = await postTransfer(req('/api/transfers', init));
    expect(first.status).toBe(201);
    const second = await postTransfer(req('/api/transfers', init));
    expect(second.status).toBe(200);
    expect(second.headers.get('Idempotent-Replayed')).toBe('true');
    expect((await repo.getAccount('user-1', 'acc_a'))?.balance).toBe(90);
  });

  it('maps business errors to 422 with code', async () => {
    const res = await postTransfer(
      req('/api/transfers', {
        method: 'POST',
        token: 'good',
        headers: { 'Idempotency-Key': 'key-12345678' },
        body: JSON.stringify({ fromAccountId: 'acc_a', toAccountId: 'acc_b', amount: 1000 }),
      }),
    );
    expect(res.status).toBe(422);
    expect((await res.json()).error.code).toBe('insufficient_funds');
  });

  it('returns 422 onboarding_required for unknown customers', async () => {
    repo.customers.clear();
    const res = await getAccounts(req('/api/accounts', { token: 'good' }));
    expect(res.status).toBe(422);
    expect((await res.json()).error.code).toBe('onboarding_required');
  });
});
