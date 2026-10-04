import { badRequest, json, notFound } from '../../../src/http.js';
import { requireCustomer, route } from '../../../src/infra/route.js';

export const GET = route({ name: 'GET /api/accounts/:id/movements' }, async (ctx) => {
  await requireCustomer(ctx);
  // /api/accounts/{id}/movements
  const accountId = decodeURIComponent(ctx.url.pathname.split('/')[3] ?? '');
  if (!accountId) throw badRequest('Cuenta inválida');
  if (!(await ctx.deps.repo.getAccount(ctx.uid, accountId))) throw notFound('Cuenta no encontrada');

  const limitParam = Number(ctx.url.searchParams.get('limit') ?? 20);
  const limit = Number.isInteger(limitParam) ? Math.min(Math.max(limitParam, 1), 50) : 20;
  const cursor = ctx.url.searchParams.get('cursor');
  return json(await ctx.deps.repo.listMovements(ctx.uid, accountId, limit, cursor));
});
