import { badRequest, json, readJson } from '../http.js';
import { sanitizeInterests } from '../domain/segmentation.js';
import { requireCustomer, route } from '../infra/route.js';
import { profileView } from '../services/onboarding.js';

export const PATCH = route({ name: 'PATCH /api/me/preferences' }, async (ctx) => {
  const customer = await requireCustomer(ctx);
  const body = await readJson(ctx.req);
  if (!Array.isArray(body.interests)) throw badRequest('"interests" debe ser una lista');
  const interests = sanitizeInterests(body.interests);
  await ctx.deps.repo.updateInterests(ctx.uid, interests);
  return json(profileView({ ...customer, preferences: { ...customer.preferences, interests } }));
});
