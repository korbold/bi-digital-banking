import { HttpError } from '../http.js';
import { cents } from '../rng.js';
import type { Segment } from '../types.js';

export type InsuranceProduct = 'travel' | 'device' | 'life';
export const INSURANCE_PRODUCTS: readonly InsuranceProduct[] = ['travel', 'device', 'life'];

interface ProductRule {
  minCoverage: number;
  maxCoverage: number;
  baseFee: number;
  /** Monthly rate applied to the covered amount. */
  rate: number;
}

export const PRODUCT_RULES: Record<InsuranceProduct, ProductRule> = {
  travel: { minCoverage: 1_000, maxCoverage: 50_000, baseFee: 2, rate: 0.0006 },
  device: { minCoverage: 200, maxCoverage: 3_000, baseFee: 1.5, rate: 0.006 },
  life: { minCoverage: 10_000, maxCoverage: 200_000, baseFee: 4, rate: 0.00045 },
};

const SEGMENT_FACTOR: Record<Segment, number> = { young: 0.9, retail: 1, premium: 0.85, business: 1 };

export interface Quote {
  quoteId: string;
  product: InsuranceProduct;
  coverage: number;
  monthlyPremium: number;
  currency: 'USD';
  validUntil: string;
}

/** Monthly premium = (base fee + coverage * rate) * segment discount. */
export function quoteInsurance(
  product: InsuranceProduct,
  coverage: number,
  segment: Segment,
  now: Date,
  newId: () => string,
): Quote {
  const rule = PRODUCT_RULES[product];
  if (coverage < rule.minCoverage || coverage > rule.maxCoverage) {
    throw new HttpError(
      422,
      'invalid_amount',
      `La cobertura para ${product} debe estar entre $${rule.minCoverage} y $${rule.maxCoverage}`,
    );
  }
  const monthlyPremium = cents((rule.baseFee + coverage * rule.rate) * SEGMENT_FACTOR[segment]);
  return {
    quoteId: newId(),
    product,
    coverage,
    monthlyPremium,
    currency: 'USD',
    validUntil: new Date(now.getTime() + 7 * 86_400_000).toISOString(),
  };
}
