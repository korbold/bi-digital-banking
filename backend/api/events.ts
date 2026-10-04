import { empty, oneOf, readJson, requireString } from '../src/http.js';
import { route } from '../src/infra/route.js';
import type { EventType } from '../src/types.js';

const EVENT_TYPES: readonly EventType[] = ['action_used', 'screen_view'];

export const POST = route({ name: 'POST /api/events' }, async (ctx) => {
  const body = await readJson(ctx.req);
  await ctx.deps.repo.recordEvent(ctx.uid, {
    type: oneOf(body.type, EVENT_TYPES, 'type'),
    target: requireString(body, 'target', { max: 64 }),
    at: new Date().toISOString(),
  });
  return empty(202);
});
