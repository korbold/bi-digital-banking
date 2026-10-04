import { json } from '../http.js';
import { route } from '../infra/route.js';

export const GET = route({ name: 'GET /api/health', auth: false }, async () =>
  json({ status: 'ok', time: new Date().toISOString(), version: process.env.VERCEL_GIT_COMMIT_SHA?.slice(0, 7) || process.env.VERCEL_DEPLOYMENT_ID?.slice(4, 12) || 'local' }),
);
