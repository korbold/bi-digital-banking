import { beforeEach, describe, expect, it, vi } from 'vitest';
import { HttpError } from '../src/http.js';
import { MemoryBankRepository } from '../src/repo/memory.js';
import type { Notifier } from '../src/services/notifier.js';
import { lookupBeneficiary, transfer } from '../src/services/transfers.js';
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
    expect(result.kind === 'own' && result.to.balance).toBe(0.1);
  });
});

describe('third-party transfer', () => {
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
    await repo.createCustomer(customer(), [account('acc_a', 100)], []);
    await repo.createCustomer(
      customer({ uid: 'user-2', name: 'María Fernanda López' }),
      [account('acc_m', 10, { accountNumber: '2299990001', number: '****0001' })],
      [],
    );
    notifier = { sendToUser: vi.fn().mockResolvedValue({ sent: 1, failed: 0, removedTokens: 0 }) };
  });

  const byNumber = (amount: number, toAccountNumber = '2299990001') => ({
    fromAccountId: 'acc_a',
    toAccountNumber,
    amount,
    description: 'Almuerzo',
  });

  it('moves money between customers without disclosing the recipient balance', async () => {
    const { result } = await transfer(UID, KEY, byNumber(25), deps());

    expect(result).toEqual({
      transferId: 'trf_1',
      kind: 'third_party',
      from: { id: 'acc_a', balance: 75 },
      to: { accountNumber: '****0001', holderName: 'María F.' },
      createdAt: '2026-10-04T15:00:00.000Z',
    });
    expect((await repo.getAccount('user-2', 'acc_m'))?.balance).toBe(35);
    const received = await repo.listMovements('user-2', 'acc_m', 10);
    expect(received.items[0]).toMatchObject({ amount: 25, description: 'Almuerzo · de Danny B.' });
    const sent = await repo.listMovements(UID, 'acc_a', 10);
    expect(sent.items[0]).toMatchObject({ amount: -25, description: 'Almuerzo · a María F. ****0001' });
  });

  it('notifies both sender and recipient', async () => {
    await transfer(UID, KEY, byNumber(5), deps());
    expect(notifier.sendToUser).toHaveBeenCalledWith(UID, expect.objectContaining({ title: 'Transferencia realizada' }));
    expect(notifier.sendToUser).toHaveBeenCalledWith(
      'user-2',
      expect.objectContaining({
        title: 'Recibiste una transferencia',
        body: 'Danny B. te envió $5.00',
        data: { type: 'transfer_received', route: '/accounts/acc_m' },
      }),
    );
  });

  it('rejects unknown account numbers and leaves balances untouched', async () => {
    await expect(transfer(UID, KEY, byNumber(5, '2200000000'), deps())).rejects.toMatchObject({
      status: 404,
      code: 'beneficiary_not_found',
    });
    expect((await repo.getAccount(UID, 'acc_a'))?.balance).toBe(100);
  });

  it('rejects sending to the same account by number', async () => {
    await expect(transfer(UID, KEY, byNumber(5, '2200001234'), deps())).rejects.toMatchObject({ code: 'same_account' });
  });

  it('is idempotent across customers', async () => {
    await transfer(UID, KEY, byNumber(5), deps());
    const replay = await transfer(UID, KEY, byNumber(5), deps());
    expect(replay.replayed).toBe(true);
    expect((await repo.getAccount('user-2', 'acc_m'))?.balance).toBe(15);
  });

  it('requires exactly one destination', async () => {
    await expect(
      transfer(UID, KEY, { ...byNumber(5), toAccountId: 'acc_b' }, deps()),
    ).rejects.toBeInstanceOf(HttpError);
  });
});

describe('lookupBeneficiary', () => {
  it('returns a masked preview and flags own accounts', async () => {
    const repo = new MemoryBankRepository();
    await repo.createCustomer(customer(), [account('acc_a', 100)], []);
    await repo.createCustomer(
      customer({ uid: 'user-2', name: 'María López' }),
      [account('acc_m', 10, { accountNumber: '2299990001', number: '****0001' })],
      [],
    );
    expect(await lookupBeneficiary(UID, '2299990001', repo)).toEqual({
      accountNumber: '2299990001',
      maskedNumber: '****0001',
      holderName: 'María L.',
      type: 'savings',
      isOwn: false,
      accountId: null,
    });
    expect(await lookupBeneficiary(UID, '2200001234', repo)).toMatchObject({ isOwn: true, accountId: 'acc_a' });
    await expect(lookupBeneficiary(UID, '123', repo)).rejects.toMatchObject({ status: 400 });
    await expect(lookupBeneficiary(UID, '2211111111', repo)).rejects.toMatchObject({ code: 'beneficiary_not_found' });
  });
});
