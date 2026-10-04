import { json } from '../http.js';
import { getDeps } from '../infra/container.js';
import { route } from '../infra/route.js';

type Check = { name: string; status: 'up' | 'degraded' | 'down'; latencyMs: number; detail?: string };

async function probe(name: string, fn: () => Promise<string | void>, timeoutMs = 3000): Promise<Check> {
  const started = Date.now();
  try {
    const detail = await Promise.race([
      fn(),
      new Promise<never>((_, reject) => setTimeout(() => reject(new Error('timeout')), timeoutMs)),
    ]);
    return { name, status: 'up', latencyMs: Date.now() - started, ...(detail ? { detail } : {}) };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return { name, status: message === 'timeout' ? 'degraded' : 'down', latencyMs: Date.now() - started, detail: message };
  }
}

/**
 * Public dependency status for the status page and uptime monitors.
 * Exposes no customer data: Firestore is probed with a read of a document
 * that never exists, and FX with a single-currency lookup.
 */
export const GET = route({ name: 'GET /api/status', auth: false }, async () => {
  const deps = getDeps();
  const checks = await Promise.all([
    probe('firestore', async () => {
      await deps.repo.getCustomer('status-probe');
    }),
    probe('fx_provider', async () => {
      const rates = await deps.fx.getRates('USD', ['EUR']);
      return rates.stale ? 'serving cached rates' : undefined;
    }),
  ]);
  const overall = checks.every((c) => c.status === 'up')
    ? 'operational'
    : checks.some((c) => c.status === 'down')
      ? 'partial_outage'
      : 'degraded';
  return json({ status: overall, time: new Date().toISOString(), checks });
});
