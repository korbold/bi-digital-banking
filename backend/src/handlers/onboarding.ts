import { json, readJson } from '../http.js';
import { route } from '../infra/route.js';
import { onboard, profileView } from '../services/onboarding.js';

export const POST = route({ name: 'POST /api/onboarding' }, async (ctx) => {
  const { customer, created } = await onboard(ctx.deps.repo, ctx.uid, ctx.email, await readJson(ctx.req));
  ctx.log({ level: 'info', msg: created ? 'customer_onboarded' : 'onboarding_replayed', segment: customer.segment });
  return json(profileView(customer), created ? 201 : 200);
});
