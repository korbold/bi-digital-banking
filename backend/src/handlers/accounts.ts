import { json } from '../http.js';
import { requireCustomer, route } from '../infra/route.js';

export const GET = route({ name: 'GET /api/accounts' }, async (ctx) => {
  await requireCustomer(ctx);
  const items = await ctx.deps.repo.listAccounts(ctx.uid);
  return json({ items });
});
