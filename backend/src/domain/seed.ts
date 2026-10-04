import { cents, hashString, mulberry32, pick, randomInt, type Rng } from '../rng.js';
import type { Account, Movement } from '../types.js';

/**
 * Generates the demo bank history for a new customer: a savings and a
 * checking account with ~25 realistic Ecuadorian movements over the last
 * 45 days. Deterministic per (uid, now) so tests and re-onboarding are stable.
 *
 * Balances are computed by replaying movements chronologically, so
 * `balanceAfter` is always consistent with the final account balance.
 */

interface Merchant {
  description: string;
  category: string;
  min: number;
  max: number;
}

const CHECKING_MERCHANTS: readonly Merchant[] = [
  { description: 'Supermaxi', category: 'groceries', min: 18, max: 95 },
  { description: 'Megamaxi', category: 'groceries', min: 25, max: 140 },
  { description: 'Tía', category: 'groceries', min: 8, max: 45 },
  { description: 'Kywi', category: 'home', min: 6, max: 80 },
  { description: 'Claro - Plan móvil', category: 'utilities', min: 18, max: 35 },
  { description: 'CNEL EP - Luz', category: 'utilities', min: 20, max: 60 },
  { description: 'EPMAPS - Agua', category: 'utilities', min: 9, max: 25 },
  { description: 'Uber', category: 'transport', min: 2.5, max: 14 },
  { description: 'Gasolinera Primax', category: 'transport', min: 10, max: 40 },
  { description: 'KFC', category: 'food', min: 6, max: 22 },
  { description: 'Juan Valdez Café', category: 'food', min: 3, max: 9 },
  { description: 'Pedidos Ya', category: 'food', min: 7, max: 28 },
  { description: 'Fybeca', category: 'health', min: 5, max: 45 },
  { description: 'Netflix', category: 'entertainment', min: 7.99, max: 15.99 },
  { description: 'Spotify', category: 'entertainment', min: 5.99, max: 5.99 },
  { description: 'De Prati', category: 'shopping', min: 20, max: 120 },
  { description: 'Amazon', category: 'shopping', min: 15, max: 90 },
];

export const CATEGORY_LABELS: Record<string, string> = {
  groceries: 'supermercado',
  home: 'hogar',
  utilities: 'servicios básicos',
  transport: 'transporte',
  food: 'comida',
  health: 'salud',
  entertainment: 'entretenimiento',
  shopping: 'compras',
  transfer: 'transferencias',
  income: 'ingresos',
  interest: 'intereses',
};

interface Draft {
  account: 'savings' | 'checking';
  date: Date;
  description: string;
  amount: number;
  category: string;
}

export interface SeedResult {
  accounts: Account[];
  movements: Movement[];
}

function accountNumber(rng: Rng): string {
  return `****${randomInt(rng, 1000, 9999)}`;
}

function atLocalTime(base: Date, daysAgo: number, rng: Rng): Date {
  const d = new Date(base.getTime() - daysAgo * 86_400_000);
  // Between 08:00 and 18:59 Ecuador time (UTC-5 => 13:00-23:59 UTC).
  d.setUTCHours(randomInt(rng, 13, 23), randomInt(rng, 0, 59), randomInt(rng, 0, 59), 0);
  return d;
}

export function generateSeed(uid: string, now: Date = new Date()): SeedResult {
  const rng = mulberry32(hashString(uid));
  const salary = cents(randomInt(rng, 900, 2200) + randomInt(rng, 0, 99) / 100);
  const ids = { savings: `acc_${uid.slice(0, 6)}_sav`, checking: `acc_${uid.slice(0, 6)}_chk` };

  const drafts: Draft[] = [];

  // Opening balances 45 days ago.
  drafts.push({
    account: 'savings',
    date: atLocalTime(now, 45, rng),
    description: 'Saldo inicial',
    amount: cents(randomInt(rng, 800, 4000) + rng()),
    category: 'income',
  });
  drafts.push({
    account: 'checking',
    date: atLocalTime(now, 45, rng),
    description: 'Saldo inicial',
    amount: cents(randomInt(rng, 150, 600) + rng()),
    category: 'income',
  });

  // Payroll on the last ~30 and ~0-2 days (two pay days in the window).
  for (const daysAgo of [31, 1]) {
    drafts.push({
      account: 'checking',
      date: atLocalTime(now, daysAgo, rng),
      description: 'Nómina - Acreditación sueldo',
      amount: salary,
      category: 'income',
    });
  }

  // Monthly savings transfer after each payday.
  for (const daysAgo of [30, 1]) {
    const amount = cents(salary * 0.1);
    const date = atLocalTime(now, daysAgo, rng);
    drafts.push({ account: 'checking', date, description: 'Transferencia a Cuenta de Ahorros', amount: -amount, category: 'transfer' });
    drafts.push({ account: 'savings', date, description: 'Transferencia desde Cuenta Corriente', amount, category: 'transfer' });
  }

  // Interest on savings.
  drafts.push({
    account: 'savings',
    date: atLocalTime(now, 15, rng),
    description: 'Intereses ganados',
    amount: cents(randomInt(rng, 1, 9) + rng()),
    category: 'interest',
  });

  // Card / debit purchases filling up to ~25 movements.
  const purchases = 25 - drafts.length + 1;
  for (let i = 0; i < purchases; i++) {
    const merchant = pick(rng, CHECKING_MERCHANTS);
    const amount = cents(merchant.min + rng() * (merchant.max - merchant.min));
    drafts.push({
      account: 'checking',
      date: atLocalTime(now, randomInt(rng, 0, 43), rng),
      description: merchant.description,
      amount: -amount,
      category: merchant.category,
    });
  }

  // Never generate a future movement (today's random hour may be later than now).
  for (const d of drafts) if (d.date.getTime() > now.getTime()) d.date = new Date(now.getTime() - 60_000);

  drafts.sort((a, b) => a.date.getTime() - b.date.getTime());

  const balances = { savings: 0, checking: 0 };
  const movements: Movement[] = [];
  for (const d of drafts) {
    const previous = balances[d.account];
    if (previous + d.amount < 0) {
      // Keep the demo realistic: a purchase never overdraws the account.
      // Shrink it to half of what is left, or drop it if that is pocket change.
      const shrunk = cents(previous * 0.5);
      if (shrunk < 1) continue;
      d.amount = -shrunk;
    }
    balances[d.account] = cents(previous + d.amount);
    movements.push({
      id: `mov_${uid.slice(0, 6)}_${String(movements.length).padStart(3, '0')}`,
      accountId: ids[d.account],
      date: d.date.toISOString(),
      description: d.description,
      amount: d.amount,
      category: d.category,
      balanceAfter: balances[d.account],
      transferId: null,
    });
  }

  const createdAt = new Date(now.getTime() - 45 * 86_400_000).toISOString();
  const accounts: Account[] = [
    {
      id: ids.savings,
      type: 'savings',
      alias: 'Cuenta de Ahorros',
      number: accountNumber(rng),
      currency: 'USD',
      balance: balances.savings,
      available: balances.savings,
      createdAt,
    },
    {
      id: ids.checking,
      type: 'checking',
      alias: 'Cuenta Corriente',
      number: accountNumber(rng),
      currency: 'USD',
      balance: balances.checking,
      available: balances.checking,
      createdAt,
    },
  ];

  return { accounts, movements };
}
