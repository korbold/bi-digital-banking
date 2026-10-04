import { json } from '../src/http.js';
import { route } from '../src/infra/route.js';

export const GET = route({ name: 'GET /api/fx' }, async (ctx) => {
  const base = ctx.url.searchParams.get('base') ?? 'USD';
  const symbols = ctx.url.searchParams.get('symbols')?.split(',').filter(Boolean);
  const rates = await ctx.deps.fx.getRates(base, symbols);
  return json(rates, 200, rates.stale ? { Warning: '110 - "Response is stale"' } : {});
});
