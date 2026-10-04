import { beforeEach, describe, expect, it, vi } from 'vitest';
import { HttpError } from '../src/http.js';
import { MemoryBankRepository } from '../src/repo/memory.js';
import type { Notifier } from '../src/services/notifier.js';
import { transfer } from '../src/services/transfers.js';
import { account, customer } from './fixtures.js';

const UID = 'user-1';
const KEY = 'idem-key-0001';

describe('transfer', () => {
  let repo: MemoryBankRepository;
  let notifier: Notifier & { sendToUser: ReturnType<typeof vi.fn> };
  let counter: number;
  const deps = () => ({
    repo,
    notifier,
    now: () => new Date('2026-10-04T15:00:00.000Z'),
    newId: (p: string) => `${p}_${++counter}`,
  });

  beforeEach(async () => {
    counter = 0;
    repo = new MemoryBankRepository();
    await repo.createCustomer(customer(), [account('acc_a', 100), account('acc_b', 50)], []);
    notifier = { sendToUser: vi.fn().mockResolvedValue({ sent: 1, failed: 0, removedTokens: 0 }) };
  });

  const input = (amount: number, overrides = {}) => ({
    fromAccountId: 'acc_a',
    toAccountId: 'acc_b',
    amount,
    description: 'Ahorro',
    ...overrides,
  });

  it('moves money atomically and records both movements', async () => {
    const { result, replayed } = await transfer(UID, KEY, input(25.5), deps());

    expect(replayed).toBe(false);
    expect(result.from).toEqual({ id: 'acc_a', balance: 74.5 });
    expect(result.to).toEqual({ id: 'acc_b', balance: 75.5 });
    expect((await repo.getAccount(UID, 'acc_a'))?.balance).toBe(74.5);
    expect((await repo.getAccount(UID, 'acc_b'))?.balance).toBe(75.5);

    const movements = repo.movements.get(UID)!;
    expect(movements).toHaveLength(2);
    expect(movements.map((m) => m.amount)).toEqual([-25.5, 25.5]);
    expect(new Set(movements.map((m) => m.transferId))).toEqual(new Set([result.transferId]));
    expect(notifier.sendToUser).toHaveBeenCalledOnce();
  });

  it('rejects insufficient funds without touching balances', async () => {
    await expect(transfer(UID, KEY, input(100.01), deps())).rejects.toMatchObject({
      status: 422,
      code: 'insufficient_funds',
    });
    expect((await repo.getAccount(UID, 'acc_a'))?.balance).toBe(100);
    expect((await repo.getAccount(UID, 'acc_b'))?.balance).toBe(50);
    expect(repo.movements.get(UID)).toEqual([]);
    expect(notifier.sendToUser).not.toHaveBeenCalled();
  });

  it('rejects same-account transfers', async () => {
    await expect(transfer(UID, KEY, input(10, { toAccountId: 'acc_a' }), deps())).rejects.toMatchObject({
      code: 'same_account',
    });
  });

  it.each([0, -5, 1.234, 10_000.01])('rejects invalid amount %s', async (amount) => {
    await expect(transfer(UID, KEY, input(amount), deps())).rejects.toMatchObject({ code: 'invalid_amount' });
  });

  it('requires an idempotency key', async () => {
    await expect(transfer(UID, null, input(10), deps())).rejects.toBeInstanceOf(HttpError);
  });

  it('replays the same key without moving money twice', async () => {
    const first = await transfer(UID, KEY, input(10), deps());
    const second = await transfer(UID, KEY, input(10), deps());

    expect(second.replayed).toBe(true);
    expect(second.result).toEqual(first.result);
    expect((await repo.getAccount(UID, 'acc_a'))?.balance).toBe(90);
    expect(repo.movements.get(UID)).toHaveLength(2);
    expect(notifier.sendToUser).toHaveBeenCalledOnce();
  });

  it('rejects a reused key with a different payload', async () => {
    await transfer(UID, KEY, input(10), deps());
    await expect(transfer(UID, KEY, input(11), deps())).rejects.toMatchObject({
      status: 409,
      code: 'idempotency_conflict',
    });
  });

  it('returns not_found for unknown accounts', async () => {
    await expect(transfer(UID, KEY, input(10, { toAccountId: 'acc_zzz' }), deps())).rejects.toMatchObject({
      status: 404,
    });
  });

  it('does not fail the transfer when the push fails', async () => {
    notifier.sendToUser.mockRejectedValue(new Error('fcm down'));
    const log = vi.fn();
    const { replayed } = await transfer(UID, KEY, input(10), { ...deps(), log });
    expect(replayed).toBe(false);
    await new Promise((r) => setTimeout(r, 0));
    expect(log).toHaveBeenCalledWith(expect.objectContaining({ msg: 'push_failed' }));
  });

  it('keeps cents exact (0.1 + 0.2 style drift)', async () => {
    await repo.createCustomer(customer(), [account('acc_a', 0.3), account('acc_b', 0)], []);
    const { result } = await transfer(UID, KEY, input(0.1), deps());
    expect(result.from.balance).toBe(0.2);
    expect(result.to.balance).toBe(0.1);
  });
});
