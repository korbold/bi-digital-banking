import { cents } from '../rng.js';
import type {
  BehaviorEvent,
  Customer,
  Experience,
  Movement,
  SduiAction,
  SduiScreen,
  SduiSection,
  Segment,
} from '../types.js';
import { CATEGORY_LABELS } from './seed.js';
import { firstName } from './segmentation.js';
import { greetingFor, startOfLocalMonth } from './time.js';

/**
 * Personalization engine: turns customer profile + behaviour + real
 * movements + business-managed experiences into an SDUI home screen.
 *
 * Pure function (no I/O) so every rule is unit-testable; the handler only
 * gathers the inputs.
 */

/** Section types the current client renderer understands (SDUI v1). */
export const KNOWN_SECTION_TYPES = new Set([
  'greeting',
  'account_summary',
  'quick_actions',
  'spending_insight',
  'promo_banner',
  'fx_rates',
  'miniapp_grid',
  'text_card',
]);

export const MAX_EXPERIENCES = 3;

const SEGMENT_THEME: Record<Segment, string> = {
  retail: '#F07F09',
  young: '#7C4DFF',
  premium: '#8A6D3B',
  business: '#0B57D0',
};

const SEGMENT_TIPS: Record<Segment, { title: string; body: string }> = {
  young: {
    title: 'Tu primer fondo de emergencia',
    body: 'Separar el 10% de cada ingreso apenas llega es la forma más fácil de ahorrar sin pensarlo.',
  },
  retail: {
    title: 'Consejo de seguridad',
    body: 'Nunca compartas tus claves ni códigos de verificación. El banco jamás te los pedirá por teléfono.',
  },
  premium: {
    title: 'Tu asesor te espera',
    body: 'Agenda una revisión de tu portafolio y descubre opciones de inversión a plazo fijo.',
  },
  business: {
    title: 'Flujo de caja',
    body: 'Programa tus pagos a proveedores para mantener liquidez a fin de mes.',
  },
};

interface QuickAction {
  id: string;
  label: string;
  icon: string;
  action: SduiAction;
}

export const DEFAULT_QUICK_ACTIONS: readonly QuickAction[] = [
  { id: 'transfer', label: 'Transferir', icon: 'swap_horiz', action: { type: 'navigate', route: '/transfer' } },
  { id: 'movements', label: 'Movimientos', icon: 'receipt_long', action: { type: 'navigate', route: '/accounts' } },
  { id: 'insurance', label: 'Seguros', icon: 'shield', action: { type: 'open_miniapp', miniappId: 'insurance' } },
  { id: 'profile', label: 'Mi perfil', icon: 'person', action: { type: 'navigate', route: '/profile' } },
];

/** Default campaigns used when the `experiences` collection is empty. */
export const DEFAULT_EXPERIENCES: readonly Experience[] = [
  {
    id: 'exp_travel_insurance',
    active: true,
    priority: 80,
    segments: [],
    interests: ['travel'],
    section: {
      id: 'exp_travel_insurance',
      type: 'promo_banner',
      minAppVersion: 1,
      props: {
        title: 'Viaja protegido',
        body: 'Cotiza tu seguro de viaje en menos de un minuto, sin papeleo.',
        background: '#0B57D0',
        cta: { label: 'Cotizar', action: { type: 'open_miniapp', miniappId: 'insurance', params: { product: 'travel' } } },
      },
    },
  },
  {
    id: 'exp_premium_card',
    active: true,
    priority: 90,
    segments: ['premium'],
    interests: [],
    section: {
      id: 'exp_premium_card',
      type: 'promo_banner',
      minAppVersion: 1,
      props: {
        title: 'Tarjeta Infinite preaprobada',
        body: 'Acceso a salas VIP y 2x en millas por tus consumos.',
        background: '#1F1B16',
        cta: { label: 'Conocer más', action: { type: 'navigate', route: '/profile' } },
      },
    },
  },
  {
    id: 'exp_savings_goal',
    active: true,
    priority: 70,
    segments: ['young'],
    interests: [],
    section: {
      id: 'exp_savings_goal',
      type: 'promo_banner',
      minAppVersion: 1,
      props: {
        title: 'Crea tu meta de ahorro',
        body: 'Ahorra para tu próximo viaje o tu primer auto con transferencias automáticas.',
        background: '#5E35B1',
        cta: { label: 'Empezar', action: { type: 'navigate', route: '/transfer' } },
      },
    },
  },
  {
    id: 'exp_device_insurance',
    active: true,
    priority: 60,
    segments: [],
    interests: ['tech'],
    section: {
      id: 'exp_device_insurance',
      type: 'promo_banner',
      minAppVersion: 1,
      props: {
        title: 'Protege tu celular',
        body: 'Cubre robo y daño accidental desde $3 al mes.',
        background: '#00796B',
        cta: { label: 'Cotizar', action: { type: 'open_miniapp', miniappId: 'insurance', params: { product: 'device' } } },
      },
    },
  },
];

export interface HomeInput {
  customer: Customer;
  /** Behaviour events of the last 30 days. */
  events: BehaviorEvent[];
  /** Movements since the start of the previous local month, all accounts. */
  movements: Movement[];
  /** Experiences from Firestore; empty -> DEFAULT_EXPERIENCES. */
  experiences: Experience[];
  now: Date;
  baseUrl: string;
}

/** Orders quick actions by how often the customer used them; ties keep the default order. */
export function rankQuickActions(events: BehaviorEvent[], actions: readonly QuickAction[] = DEFAULT_QUICK_ACTIONS): QuickAction[] {
  const usage = new Map<string, number>();
  for (const e of events) {
    if (e.type === 'action_used') usage.set(e.target, (usage.get(e.target) ?? 0) + 1);
  }
  return actions
    .map((action, index) => ({ action, index, uses: usage.get(action.id) ?? 0 }))
    .sort((a, b) => b.uses - a.uses || a.index - b.index)
    .map((x) => x.action);
}

/** Active, in-date, targeted at this customer, of a known type; highest priority first. */
export function selectExperiences(experiences: readonly Experience[], customer: Customer, now: Date): Experience[] {
  const t = now.getTime();
  return experiences
    .filter((e) => e.active)
    .filter((e) => KNOWN_SECTION_TYPES.has(e.section?.type))
    .filter((e) => !e.startsAt || Date.parse(e.startsAt) <= t)
    .filter((e) => !e.endsAt || Date.parse(e.endsAt) > t)
    .filter((e) => e.segments.length === 0 || e.segments.includes(customer.segment))
    .filter((e) => e.interests.length === 0 || e.interests.some((i) => customer.preferences.interests.includes(i)))
    .sort((a, b) => b.priority - a.priority)
    .slice(0, MAX_EXPERIENCES);
}

export interface SpendingInsight {
  category: string;
  current: number;
  previous: number;
  /** Percentage change vs previous month, null when there is no baseline. */
  changePct: number | null;
}

/** Top spending category this month compared with the same category last month. */
export function spendingInsight(movements: readonly Movement[], now: Date): SpendingInsight | null {
  const thisMonth = startOfLocalMonth(now).getTime();
  const lastMonth = startOfLocalMonth(now, 1).getTime();
  const current = new Map<string, number>();
  const previous = new Map<string, number>();

  for (const m of movements) {
    if (m.amount >= 0 || m.category === 'transfer') continue;
    const t = Date.parse(m.date);
    const bucket = t >= thisMonth ? current : t >= lastMonth ? previous : null;
    if (bucket) bucket.set(m.category, (bucket.get(m.category) ?? 0) - m.amount);
  }

  let top: [string, number] | null = null;
  for (const entry of current) if (!top || entry[1] > top[1]) top = entry;
  if (!top) return null;

  const [category, amount] = top;
  const before = previous.get(category) ?? 0;
  return {
    category,
    current: cents(amount),
    previous: cents(before),
    changePct: before > 0 ? Math.round(((amount - before) / before) * 100) : null,
  };
}

function insightSection(insight: SpendingInsight): SduiSection {
  const label = CATEGORY_LABELS[insight.category] ?? insight.category;
  const amount = `$${insight.current.toFixed(2)}`;
  let comparison = '';
  if (insight.changePct !== null) {
    comparison =
      insight.changePct === 0
        ? ', igual que el mes pasado'
        : `, ${Math.abs(insight.changePct)}% ${insight.changePct < 0 ? 'menos' : 'más'} que el mes pasado`;
  }
  return {
    id: 'insight',
    type: 'spending_insight',
    props: {
      title: 'Este mes',
      body: `Gastaste ${amount} en ${label}${comparison}`,
      category: insight.category,
      amount: insight.current,
      changePct: insight.changePct,
    },
  };
}

export function buildHome(input: HomeInput): SduiScreen {
  const { customer, now, baseUrl } = input;
  const base = baseUrl.replace(/\/$/, '');
  const sections: SduiSection[] = [];

  sections.push({
    id: 'greeting',
    type: 'greeting',
    props: { title: `${greetingFor(now)}, ${firstName(customer.name)}`, subtitle: 'Tu resumen de hoy' },
  });
  sections.push({ id: 'accounts', type: 'account_summary', props: {} });
  sections.push({ id: 'quick', type: 'quick_actions', props: { actions: rankQuickActions(input.events) } });

  const insight = spendingInsight(input.movements, now);
  if (insight) sections.push(insightSection(insight));

  const catalog = input.experiences.length > 0 ? input.experiences : DEFAULT_EXPERIENCES;
  for (const exp of selectExperiences(catalog, customer, now)) {
    sections.push({ ...exp.section, id: exp.id });
  }

  sections.push({ id: 'fx', type: 'fx_rates', props: { base: 'USD', symbols: ['EUR', 'COP', 'PEN'] } });
  sections.push({
    id: 'miniapps',
    type: 'miniapp_grid',
    props: {
      items: [{ id: 'insurance', title: 'Seguros', icon: 'shield', url: `${base}/miniapps/insurance/` }],
    },
  });
  sections.push({ id: 'tip', type: 'text_card', props: SEGMENT_TIPS[customer.segment] });

  return {
    schemaVersion: 1,
    screen: 'home',
    generatedAt: now.toISOString(),
    segment: customer.segment,
    theme: { seed: SEGMENT_THEME[customer.segment] },
    sections,
  };
}
