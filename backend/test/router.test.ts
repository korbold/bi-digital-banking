import { describe, expect, it } from 'vitest';
import { dispatch, resolve } from '../src/router.js';

describe('router', () => {
  it('resolves static and parameterised routes per method', () => {
    expect(typeof resolve('GET', '/api/accounts')).toBe('function');
    expect(typeof resolve('GET', '/api/accounts/acc_1/movements')).toBe('function');
    expect(typeof resolve('POST', '/api/transfers')).toBe('function');
    expect(resolve('DELETE', '/api/transfers')).toBe('method_not_allowed');
    expect(resolve('GET', '/api/nope')).toBeNull();
  });

  it('restores the original path from the rewrite query parameter', async () => {
    const res = await dispatch(new Request('https://bff.test/api?__path=health'));
    expect(res.status).toBe(200);
    expect((await res.json()).status).toBe('ok');
  });

  it('returns the error envelope for unknown routes', async () => {
    const res = await dispatch(new Request('https://bff.test/api?__path=unknown/route'));
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: { code: 'not_found', message: 'Ruta no encontrada' } });
  });
});

describe('router rewrite quirks', () => {
  it('ignores stray whitespace appended by the platform rewrite', async () => {
    const res = await dispatch(new Request('https://bff.test/api?__path=health%20'));
    expect(res.status).toBe(200);
  });
});
