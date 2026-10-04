import { INTERESTS, type AgeRange, type Interest, type Segment } from '../types.js';

export interface OnboardingProfile {
  ageRange: AgeRange;
  monthlyIncome: number;
  interests: Interest[];
}

/**
 * Rule-based segmentation (contract):
 *   income >= 5000 -> premium, age 18-25 -> young, otherwise retail.
 * Premium wins over young: a high-income 22-year-old gets premium benefits.
 * `business` is reserved for a future company-onboarding flow.
 */
export function segmentFor(profile: Pick<OnboardingProfile, 'ageRange' | 'monthlyIncome'>): Segment {
  if (profile.monthlyIncome >= 5000) return 'premium';
  if (profile.ageRange === '18-25') return 'young';
  return 'retail';
}

/** Keeps only known interests, deduplicated, preserving order. */
export function sanitizeInterests(values: unknown): Interest[] {
  if (!Array.isArray(values)) return [];
  const allowed = new Set<string>(INTERESTS);
  const out: Interest[] = [];
  for (const v of values) {
    if (typeof v === 'string' && allowed.has(v) && !out.includes(v as Interest)) out.push(v as Interest);
  }
  return out;
}

/**
 * Ecuadorian cédula validation (10 digits, province 01-24 or 30, third digit
 * < 6 for natural persons, módulo 10 check digit).
 */
export function isValidCedula(value: string): boolean {
  if (!/^\d{10}$/.test(value)) return false;
  const province = Number(value.slice(0, 2));
  if (!((province >= 1 && province <= 24) || province === 30)) return false;
  if (Number(value[2]) >= 6) return false;
  const digits = value.split('').map(Number);
  let sum = 0;
  for (let i = 0; i < 9; i++) {
    let product = digits[i]! * (i % 2 === 0 ? 2 : 1);
    if (product > 9) product -= 9;
    sum += product;
  }
  const check = (10 - (sum % 10)) % 10;
  return check === digits[9];
}

/** "Danny Barahona" -> "Danny" for greetings. */
export function firstName(name: string): string {
  return name.trim().split(/\s+/)[0] ?? name;
}
