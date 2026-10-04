import { json } from '../src/http.js';
import { route } from '../src/infra/route.js';

export const GET = route({ name: 'GET /api/health', auth: false }, async () =>
  json({ status: 'ok', time: new Date().toISOString(), version: process.env.VERCEL_GIT_COMMIT_SHA?.slice(0, 7) ?? 'local' }),
);
