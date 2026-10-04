// Shared domain types. Mirrors docs/api-contract.md.

export type Segment = 'young' | 'retail' | 'premium' | 'business';
export type AgeRange = '18-25' | '26-40' | '41-60' | '60+';
export type AccountType = 'savings' | 'checking';
export type Platform = 'android' | 'ios';
export type EventType = 'action_used' | 'screen_view';

export const INTERESTS = [
  'travel',
  'tech',
  'savings',
  'shopping',
  'food',
  'health',
  'education',
  'investing',
] as const;
export type Interest = (typeof INTERESTS)[number];

export interface Customer {
  uid: string;
  name: string;
  email: string | null;
  documentId: string;
  segment: Segment;
  preferences: { interests: Interest[] };
  onboardingCompleted: boolean;
  createdAt: string;
}

export interface Account {
  id: string;
  type: AccountType;
  alias: string;
  number: string;
  currency: 'USD';
  balance: number;
  available: number;
  createdAt: string;
}

export interface Movement {
  id: string;
  accountId: string;
  date: string;
  description: string;
  amount: number;
  category: string;
  balanceAfter: number;
  transferId: string | null;
}

export interface BehaviorEvent {
  type: EventType;
  target: string;
  at: string;
}

export interface Device {
  token: string;
  platform: Platform;
  updatedAt: string;
}

// ---- SDUI ----

export type SduiAction =
  | { type: 'navigate'; route: string }
  | { type: 'open_miniapp'; miniappId: string; params?: Record<string, string> }
  | { type: 'open_url'; url: string };

export interface SduiSection {
  id: string;
  type: string;
  minAppVersion?: number;
  props: Record<string, unknown>;
}

export interface SduiScreen {
  schemaVersion: 1;
  screen: 'home';
  generatedAt: string;
  segment: Segment;
  theme: { seed: string };
  sections: SduiSection[];
}

export interface Experience {
  id: string;
  active: boolean;
  priority: number;
  segments: Segment[];
  interests: Interest[];
  startsAt?: string | null;
  endsAt?: string | null;
  section: SduiSection;
}

// ---- Transfers ----

export interface TransferInput {
  fromAccountId: string;
  toAccountId: string;
  amount: number;
  description: string;
}

export interface TransferResult {
  transferId: string;
  from: { id: string; balance: number };
  to: { id: string; balance: number };
  createdAt: string;
}
