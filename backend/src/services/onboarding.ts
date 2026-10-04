import { badRequest, oneOf, requireNumber, requireString } from '../http.js';
import { generateSeed } from '../domain/seed.js';
import { isValidCedula, sanitizeInterests, segmentFor } from '../domain/segmentation.js';
import type { BankRepository } from '../repo/types.js';
import type { AgeRange, Customer } from '../types.js';

const AGE_RANGES: readonly AgeRange[] = ['18-25', '26-40', '41-60', '60+'];

/**
 * Registers the customer, segments them and opens their demo accounts.
 * Idempotent per uid: a second call returns the existing profile.
 */
export async function onboard(
  repo: BankRepository,
  uid: string,
  email: string | null,
  body: Record<string, unknown>,
  now: Date = new Date(),
): Promise<{ customer: Customer; created: boolean }> {
  const existing = await repo.getCustomer(uid);
  if (existing) return { customer: existing, created: false };

  const name = requireString(body, 'name', { min: 2, max: 80 });
  const documentId = requireString(body, 'documentId', { min: 10, max: 10 });
  if (!isValidCedula(documentId)) throw badRequest('Cédula inválida');

  const profile = body.profile;
  if (!profile || typeof profile !== 'object') throw badRequest('"profile" es obligatorio');
  const p = profile as Record<string, unknown>;
  const ageRange = oneOf(p.ageRange, AGE_RANGES, 'profile.ageRange');
  const monthlyIncome = requireNumber(p, 'monthlyIncome');
  if (monthlyIncome < 0) throw badRequest('"profile.monthlyIncome" no puede ser negativo');
  const interests = sanitizeInterests(p.interests);

  const customer: Customer = {
    uid,
    name,
    email,
    documentId,
    segment: segmentFor({ ageRange, monthlyIncome }),
    preferences: { interests },
    onboardingCompleted: true,
    createdAt: now.toISOString(),
  };
  const { accounts, movements } = generateSeed(uid, now);
  await repo.createCustomer(customer, accounts, movements);
  return { customer, created: true };
}

/** Public projection of the customer (no document id). */
export function profileView(c: Customer) {
  return {
    uid: c.uid,
    name: c.name,
    email: c.email,
    segment: c.segment,
    preferences: c.preferences,
    onboardingCompleted: c.onboardingCompleted,
  };
}
