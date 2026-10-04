import { describe, expect, it } from 'vitest';
import { MemoryBankRepository } from '../src/repo/memory.js';
import { onboard } from '../src/services/onboarding.js';

const body = {
  name: 'Danny Barahona',
  documentId: '1003821293',
  profile: { ageRange: '26-40', monthlyIncome: 1500, interests: ['travel', 'unknown'] },
};

describe('onboard', () => {
  it('creates customer, segment and seeded accounts', async () => {
    const repo = new MemoryBankRepository();
    const { customer, created } = await onboard(repo, 'uid-1', 'd@x.com', body);
    expect(created).toBe(true);
    expect(customer.segment).toBe('retail');
    expect(customer.preferences.interests).toEqual(['travel']);
    expect(await repo.listAccounts('uid-1')).toHaveLength(2);
  });

  it('is idempotent per uid', async () => {
    const repo = new MemoryBankRepository();
    await onboard(repo, 'uid-1', null, body);
    const again = await onboard(repo, 'uid-1', null, { ...body, name: 'Otro' });
    expect(again.created).toBe(false);
    expect(again.customer.name).toBe('Danny Barahona');
  });

  it('rejects an invalid cédula', async () => {
    await expect(onboard(new MemoryBankRepository(), 'u', null, { ...body, documentId: '1234567890' })).rejects.toMatchObject({
      status: 400,
    });
  });
});
