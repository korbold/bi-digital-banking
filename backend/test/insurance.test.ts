import { describe, expect, it } from 'vitest';
import { quoteInsurance } from '../src/domain/insurance.js';

const NOW = new Date('2026-10-04T15:00:00.000Z');

describe('quoteInsurance', () => {
  it('prices by product rule and segment discount', () => {
    const retail = quoteInsurance('device', 1000, 'retail', NOW, () => 'q1');
    expect(retail.monthlyPremium).toBe(7.5); // 1.5 + 1000 * 0.006
    const premium = quoteInsurance('device', 1000, 'premium', NOW, () => 'q2');
    expect(premium.monthlyPremium).toBe(6.38); // 7.5 * 0.85
    expect(retail.validUntil).toBe('2026-10-11T15:00:00.000Z');
  });

  it('rejects coverage outside the product range', () => {
    expect(() => quoteInsurance('travel', 999, 'retail', NOW, () => 'q')).toThrowError(/entre/);
    expect(() => quoteInsurance('life', 300_000, 'retail', NOW, () => 'q')).toThrowError();
  });
});
