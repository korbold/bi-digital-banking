import { json } from '../http.js';
import { firstName } from '../domain/segmentation.js';
import { requireCustomer, route } from '../infra/route.js';

export const POST = route({ name: 'POST /api/notifications/test' }, async (ctx) => {
  const customer = await requireCustomer(ctx);
  const report = await ctx.deps.notifier.sendToUser(ctx.uid, {
    title: `Hola ${firstName(customer.name)} 👋`,
    body: 'Esta es una notificación de prueba de tu banca digital.',
    data: { type: 'test', route: '/home' },
  });
  return json(report);
});
