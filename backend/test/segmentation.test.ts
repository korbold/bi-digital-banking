import { describe, expect, it } from 'vitest';
import { firstName, isValidCedula, sanitizeInterests, segmentFor } from '../src/domain/segmentation.js';

describe('segmentFor', () => {
  it('assigns premium from income 5000 regardless of age', () => {
    expect(segmentFor({ ageRange: '18-25', monthlyIncome: 5000 })).toBe('premium');
    expect(segmentFor({ ageRange: '41-60', monthlyIncome: 8000 })).toBe('premium');
  });

  it('assigns young to 18-25 below the premium threshold', () => {
    expect(segmentFor({ ageRange: '18-25', monthlyIncome: 4999.99 })).toBe('young');
  });

  it('defaults to retail', () => {
    expect(segmentFor({ ageRange: '26-40', monthlyIncome: 1500 })).toBe('retail');
    expect(segmentFor({ ageRange: '60+', monthlyIncome: 0 })).toBe('retail');
  });
});

describe('sanitizeInterests', () => {
  it('keeps known interests, dedupes and preserves order', () => {
    expect(sanitizeInterests(['tech', 'crypto', 'travel', 'tech', 3])).toEqual(['tech', 'travel']);
  });

  it('returns empty for non-arrays', () => {
    expect(sanitizeInterests('travel')).toEqual([]);
  });
});

describe('isValidCedula', () => {
  it('accepts a valid cédula', () => {
    expect(isValidCedula('1003821293')).toBe(true);
    expect(isValidCedula('1710034065')).toBe(true);
  });

  it('rejects wrong check digit, province or length', () => {
    expect(isValidCedula('1003821294')).toBe(false);
    expect(isValidCedula('9903821293')).toBe(false);
    expect(isValidCedula('100382129')).toBe(false);
    expect(isValidCedula('10038212a3')).toBe(false);
  });
});

it('firstName takes the first token', () => {
  expect(firstName('  Danny   Barahona ')).toBe('Danny');
});
