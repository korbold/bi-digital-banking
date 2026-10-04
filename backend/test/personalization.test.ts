import { describe, expect, it } from 'vitest';
import {
  DEFAULT_EXPERIENCES,
  buildHome,
  rankQuickActions,
  selectExperiences,
  spendingInsight,
} from '../src/domain/personalization.js';
import type { BehaviorEvent, Experience, Movement } from '../src/types.js';
import { customer } from './fixtures.js';

const NOW = new Date('2026-10-15T20:00:00.000Z'); // 15:00 in Guayaquil

const event = (target: string, type: BehaviorEvent['type'] = 'action_used'): BehaviorEvent => ({
  type,
  target,
  at: '2026-10-10T00:00:00.000Z',
});

const experience = (id: string, overrides: Partial<Experience> = {}): Experience => ({
  id,
  active: true,
  priority: 10,
  segments: [],
  interests: [],
  section: { id, type: 'promo_banner', props: { title: id } },
  ...overrides,
});

const movement = (date: string, amount: number, category: string): Movement => ({
  id: `m_${date}_${category}_${amount}`,
  accountId: 'acc',
  date,
  description: category,
  amount,
  category,
  balanceAfter: 0,
  transferId: null,
});

describe('rankQuickActions', () => {
  it('orders by usage and keeps default order on ties', () => {
    const ranked = rankQuickActions([event('insurance'), event('insurance'), event('profile'), event('transfer', 'screen_view')]);
    expect(ranked.map((a) => a.id)).toEqual(['insurance', 'profile', 'transfer', 'movements']);
  });

  it('returns default order without events', () => {
    expect(rankQuickActions([]).map((a) => a.id)).toEqual(['transfer', 'movements', 'insurance', 'profile']);
  });
});

describe('selectExperiences', () => {
  const c = customer({ segment: 'young', preferences: { interests: ['travel'] } });

  it('filters by segment, interests, active flag and dates', () => {
    const selected = selectExperiences(
      [
        experience('for_young', { segments: ['young'] }),
        experience('for_premium', { segments: ['premium'] }),
        experience('for_travel', { interests: ['travel'] }),
        experience('for_tech', { interests: ['tech'] }),
        experience('inactive', { active: false }),
        experience('expired', { endsAt: '2026-10-01T00:00:00.000Z' }),
        experience('future', { startsAt: '2026-11-01T00:00:00.000Z' }),
        experience('running', { startsAt: '2026-10-01T00:00:00.000Z', endsAt: '2026-10-31T00:00:00.000Z' }),
      ],
      c,
      NOW,
    );
    expect(selected.map((e) => e.id).sort()).toEqual(['for_travel', 'for_young', 'running']);
  });

  it('excludes section types the client cannot render', () => {
    const unknown = experience('hologram', { section: { id: 'hologram', type: 'hologram_3d', props: {} } });
    expect(selectExperiences([unknown], c, NOW)).toEqual([]);
  });

  it('sorts by priority and caps at three', () => {
    const selected = selectExperiences(
      [1, 5, 3, 9, 7].map((p) => experience(`p${p}`, { priority: p })),
      c,
      NOW,
    );
    expect(selected.map((e) => e.id)).toEqual(['p9', 'p7', 'p5']);
  });
});

describe('spendingInsight', () => {
  it('compares the top category this month with last month', () => {
    const insight = spendingInsight(
      [
        movement('2026-10-05T15:00:00.000Z', -60, 'groceries'),
        movement('2026-10-06T15:00:00.000Z', -40, 'groceries'),
        movement('2026-10-07T15:00:00.000Z', -30, 'food'),
        movement('2026-09-10T15:00:00.000Z', -125, 'groceries'),
        movement('2026-10-08T15:00:00.000Z', -500, 'transfer'),
        movement('2026-10-01T15:00:00.000Z', 1500, 'income'),
      ],
      NOW,
    );
    expect(insight).toEqual({ category: 'groceries', current: 100, previous: 125, changePct: -20 });
  });

  it('uses Guayaquil month boundaries', () => {
    // 2026-10-01T03:00Z is still Sept 30 at 22:00 in Ecuador.
    const insight = spendingInsight([movement('2026-10-01T03:00:00.000Z', -10, 'food')], NOW);
    expect(insight).toBeNull();
  });

  it('returns null without spending this month', () => {
    expect(spendingInsight([], NOW)).toBeNull();
  });
});

describe('buildHome', () => {
  it('builds a personalised SDUI screen', () => {
    const screen = buildHome({
      customer: customer({ segment: 'premium', preferences: { interests: ['travel'] } }),
      events: [event('insurance')],
      movements: [movement('2026-10-05T15:00:00.000Z', -20, 'food')],
      experiences: [],
      now: NOW,
      baseUrl: 'https://bff.test/',
    });

    expect(screen.schemaVersion).toBe(1);
    expect(screen.segment).toBe('premium');
    expect(screen.theme.seed).toBe('#8A6D3B');
    const types = screen.sections.map((s) => s.type);
    expect(types.slice(0, 4)).toEqual(['greeting', 'account_summary', 'quick_actions', 'spending_insight']);
    expect(types.at(-1)).toBe('text_card');
    expect(screen.sections[0]?.props.title).toBe('Buenas tardes, Danny');

    const ids = screen.sections.map((s) => s.id);
    expect(ids).toContain('exp_premium_card');
    expect(ids).toContain('exp_travel_insurance');
    expect(ids.indexOf('exp_premium_card')).toBeLessThan(ids.indexOf('exp_travel_insurance'));

    const quick = screen.sections.find((s) => s.type === 'quick_actions')!;
    expect((quick.props.actions as { id: string }[])[0]?.id).toBe('insurance');

    const grid = screen.sections.find((s) => s.type === 'miniapp_grid')!;
    expect((grid.props.items as { url: string }[])[0]?.url).toBe('https://bff.test/miniapps/insurance/');
  });

  it('prefers Firestore experiences over the defaults', () => {
    const screen = buildHome({
      customer: customer(),
      events: [],
      movements: [],
      experiences: [experience('exp_black_friday', { priority: 100 })],
      now: NOW,
      baseUrl: 'https://bff.test',
    });
    const ids = screen.sections.map((s) => s.id);
    expect(ids).toContain('exp_black_friday');
    for (const d of DEFAULT_EXPERIENCES) expect(ids).not.toContain(d.id);
    expect(ids).not.toContain('insight');
  });

  it('greets by Guayaquil local time', () => {
    const morning = buildHome({
      customer: customer(),
      events: [],
      movements: [],
      experiences: [],
      now: new Date('2026-10-15T12:00:00.000Z'), // 07:00 local
      baseUrl: 'https://bff.test',
    });
    expect(morning.sections[0]?.props.title).toBe('Buenos días, Danny');
  });
});
