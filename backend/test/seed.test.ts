import { describe, expect, it } from 'vitest';
import { generateSeed } from '../src/domain/seed.js';

const NOW = new Date('2026-10-04T15:00:00.000Z');

describe('generateSeed', () => {
  it('is deterministic for the same uid and clock', () => {
    expect(generateSeed('uid-abc', NOW)).toEqual(generateSeed('uid-abc', NOW));
  });

  it('differs between customers', () => {
    expect(generateSeed('uid-abc', NOW).movements).not.toEqual(generateSeed('uid-xyz', NOW).movements);
  });

  it('creates a savings and a checking account with ~25 movements in the last 45 days', () => {
    const { accounts, movements } = generateSeed('uid-abc', NOW);
    expect(accounts.map((a) => a.type)).toEqual(['savings', 'checking']);
    expect(movements.length).toBeGreaterThanOrEqual(20);
    expect(movements.length).toBeLessThanOrEqual(30);
    const oldest = NOW.getTime() - 46 * 86_400_000;
    for (const m of movements) {
      const t = Date.parse(m.date);
      expect(t).toBeGreaterThanOrEqual(oldest);
      expect(t).toBeLessThanOrEqual(NOW.getTime());
    }
  });

  it('keeps balanceAfter consistent with the final balance and never overdraws', () => {
    const { accounts, movements } = generateSeed('uid-balance', NOW);
    for (const account of accounts) {
      const own = movements.filter((m) => m.accountId === account.id);
      const sum = Math.round(own.reduce((acc, m) => acc + m.amount, 0) * 100) / 100;
      expect(sum).toBeCloseTo(account.balance, 2);
      expect(own.at(-1)?.balanceAfter).toBe(account.balance);
      for (const m of own) expect(m.balanceAfter).toBeGreaterThanOrEqual(0);
    }
  });

  it('uses realistic local merchants', () => {
    const descriptions = generateSeed('uid-abc', NOW).movements.map((m) => m.description);
    expect(descriptions).toContain('Nómina - Acreditación sueldo');
  });
});
