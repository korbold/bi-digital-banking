import { json } from '../http.js';
import { requireCustomer, route } from '../infra/route.js';
import { profileView } from '../services/onboarding.js';

export const GET = route({ name: 'GET /api/me' }, async (ctx) => json(profileView(await requireCustomer(ctx, 404))));
