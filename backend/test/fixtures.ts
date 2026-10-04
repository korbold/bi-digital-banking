import type { Account, Customer } from '../src/types.js';

export function customer(overrides: Partial<Customer> = {}): Customer {
  return {
    uid: 'user-1',
    name: 'Danny Barahona',
    email: 'danny@example.com',
    documentId: '1003821293',
    segment: 'retail',
    preferences: { interests: [] },
    onboardingCompleted: true,
    createdAt: '2026-09-01T00:00:00.000Z',
    ...overrides,
  };
}

export function account(id: string, balance: number, overrides: Partial<Account> = {}): Account {
  return {
    id,
    type: 'savings',
    alias: id === 'acc_a' ? 'Cuenta de Ahorros' : 'Cuenta Corriente',
    accountNumber: id === 'acc_a' ? '2200001234' : id === 'acc_b' ? '1000005678' : `22${id.padEnd(8, '0').slice(0, 8)}`,
    number: '****1234',
    currency: 'USD',
    balance,
    available: balance,
    createdAt: '2026-09-01T00:00:00.000Z',
    ...overrides,
  };
}
