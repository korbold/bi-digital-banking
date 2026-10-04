import { json } from '../http.js';
import { requireCustomer, route } from '../infra/route.js';
import { lookupBeneficiary } from '../services/transfers.js';

export const GET = route({ name: 'GET /api/beneficiaries/lookup' }, async (ctx) => {
  await requireCustomer(ctx);
  const accountNumber = (ctx.url.searchParams.get('accountNumber') ?? '').trim();
  return json(await lookupBeneficiary(ctx.uid, accountNumber, ctx.deps.repo));
});
