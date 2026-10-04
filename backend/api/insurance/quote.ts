import { json, oneOf, readJson, requireNumber } from '../../src/http.js';
import { INSURANCE_PRODUCTS, quoteInsurance } from '../../src/domain/insurance.js';
import { requireCustomer, route } from '../../src/infra/route.js';

export const POST = route({ name: 'POST /api/insurance/quote' }, async (ctx) => {
  const customer = await requireCustomer(ctx);
  const body = await readJson(ctx.req);
  const quote = quoteInsurance(
    oneOf(body.product, INSURANCE_PRODUCTS, 'product'),
    requireNumber(body, 'coverage'),
    customer.segment,
    new Date(),
    () => `qte_${crypto.randomUUID().replaceAll('-', '').slice(0, 16)}`,
  );
  ctx.log({ level: 'info', msg: 'insurance_quoted', product: quote.product, premium: quote.monthlyPremium });
  return json(quote);
});
