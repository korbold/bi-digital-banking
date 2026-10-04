import { json } from '../../src/http.js';
import { requireCustomer, route } from '../../src/infra/route.js';
import { profileView } from '../../src/services/onboarding.js';

export const GET = route({ name: 'GET /api/me' }, async (ctx) => json(profileView(await requireCustomer(ctx, 404))));
