/**
 * Upserts sample experiences (campaigns) into Firestore.
 *
 * This is how the business adds content to the home without an app release:
 * write a document in `experiences/` and every targeted customer sees it on
 * the next home load.
 *
 *   FIREBASE_SERVICE_ACCOUNT=$(base64 -i sa.json | tr -d '\n') npm run seed:experiences
 */
import { DEFAULT_EXPERIENCES } from '../src/domain/personalization.js';
import { FirestoreBankRepository } from '../src/repo/firestore.js';
import { firestore } from '../src/infra/firebase.js';
import type { Experience } from '../src/types.js';

const now = new Date();
const inDays = (d: number) => new Date(now.getTime() + d * 86_400_000).toISOString();

const extra: Experience[] = [
  {
    id: 'exp_cyber_week',
    active: true,
    priority: 95,
    segments: ['retail', 'young'],
    interests: ['shopping', 'tech'],
    startsAt: now.toISOString(),
    endsAt: inDays(14),
    section: {
      id: 'exp_cyber_week',
      type: 'promo_banner',
      minAppVersion: 1,
      props: {
        title: 'Cyber Week: 12 meses sin intereses',
        body: 'En tecnología y electrodomésticos con tu tarjeta de débito.',
        background: '#C2185B',
        cta: { label: 'Ver comercios', action: { type: 'open_url', url: 'https://www.google.com/search?q=cyber+week+ecuador' } },
      },
    },
  },
  {
    id: 'exp_education_tip',
    active: true,
    priority: 40,
    segments: [],
    interests: ['education', 'savings'],
    section: {
      id: 'exp_education_tip',
      type: 'text_card',
      minAppVersion: 1,
      props: {
        title: 'Regla 50/30/20',
        body: '50% necesidades, 30% gustos, 20% ahorro. Úsala como punto de partida para tu presupuesto.',
      },
    },
  },
];

async function main() {
  const repo = new FirestoreBankRepository(firestore());
  for (const exp of [...DEFAULT_EXPERIENCES, ...extra]) {
    await repo.upsertExperience(exp);
    console.log(`upserted ${exp.id} (priority ${exp.priority})`);
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
