import { empty, oneOf, readJson, requireString } from '../src/http.js';
import { route } from '../src/infra/route.js';
import type { Platform } from '../src/types.js';

const PLATFORMS: readonly Platform[] = ['android', 'ios'];

export const POST = route({ name: 'POST /api/devices' }, async (ctx) => {
  const body = await readJson(ctx.req);
  await ctx.deps.repo.saveDevice(
    ctx.uid,
    requireString(body, 'token', { min: 20, max: 4096 }),
    oneOf(body.platform, PLATFORMS, 'platform'),
  );
  return empty(204);
});
