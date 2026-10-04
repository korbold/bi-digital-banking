import { badRequest, json, readJson, requireNumber, requireString } from '../http.js';
import { requireCustomer, route } from '../infra/route.js';
import { transfer } from '../services/transfers.js';

export const POST = route({ name: 'POST /api/transfers' }, async (ctx) => {
  await requireCustomer(ctx);
  const body = await readJson(ctx.req);
  const { result, replayed } = await transfer(
    ctx.uid,
    ctx.req.headers.get('idempotency-key'),
    {
      fromAccountId: requireString(body, 'fromAccountId', { max: 64 }),
      toAccountId: optionalString(body, 'toAccountId', 64),
      toAccountNumber: optionalString(body, 'toAccountNumber', 10),
      amount: requireNumber(body, 'amount'),
      description: typeof body.description === 'string' ? body.description : '',
    },
    { repo: ctx.deps.repo, notifier: ctx.deps.notifier, log: ctx.log },
  );
  ctx.log({ level: 'info', msg: replayed ? 'transfer_replayed' : 'transfer_completed', transferId: result.transferId });
  return json(result, replayed ? 200 : 201, replayed ? { 'Idempotent-Replayed': 'true' } : {});
});

function optionalString(body: Record<string, unknown>, key: string, max: number): string | undefined {
  const value = body[key];
  if (value === undefined || value === null || value === '') return undefined;
  if (typeof value !== 'string' || value.length > max) throw badRequest(`"${key}" inválido`);
  return value;
}
