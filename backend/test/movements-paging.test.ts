import { describe, expect, it } from 'vitest';
import { generateSeed } from '../src/domain/seed.js';
import { MemoryBankRepository } from '../src/repo/memory.js';
import { customer } from './fixtures.js';

describe('MemoryBankRepository.listMovements', () => {
  it('pages newest-first with a cursor until exhausted', async () => {
    const repo = new MemoryBankRepository();
    const { accounts, movements } = generateSeed('user-1', new Date('2026-10-04T15:00:00.000Z'));
    await repo.createCustomer(customer(), accounts, movements);
    const checking = accounts.find((a) => a.type === 'checking')!;
    const total = movements.filter((m) => m.accountId === checking.id).length;

    const seen: string[] = [];
    let cursor: string | null = null;
    do {
      const page = await repo.listMovements('user-1', checking.id, 5, cursor);
      seen.push(...page.items.map((m) => m.date));
      cursor = page.nextCursor;
    } while (cursor);

    expect(seen).toHaveLength(total);
    expect([...seen].sort().reverse()).toEqual(seen);
  });
});
