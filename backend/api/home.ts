import { json } from '../src/http.js';
import { buildHome } from '../src/domain/personalization.js';
import { startOfLocalMonth } from '../src/domain/time.js';
import { publicBaseUrl, requireCustomer, route } from '../src/infra/route.js';

const THIRTY_DAYS_MS = 30 * 86_400_000;

export const GET = route({ name: 'GET /api/home' }, async (ctx) => {
  const customer = await requireCustomer(ctx);
  const now = new Date();
  const { repo } = ctx.deps;
  const [events, movements, experiences] = await Promise.all([
    repo.listEventsSince(ctx.uid, new Date(now.getTime() - THIRTY_DAYS_MS).toISOString()),
    repo.listMovementsSince(ctx.uid, startOfLocalMonth(now, 1).toISOString()),
    repo.listActiveExperiences(),
  ]);
  return json(buildHome({ customer, events, movements, experiences, now, baseUrl: publicBaseUrl(ctx) }));
});
