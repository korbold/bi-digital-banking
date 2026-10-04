import { HttpError } from '../http.js';
import type { Account, AccountRef, BehaviorEvent, Customer, Device, Experience, Movement, Platform } from '../types.js';
import type { BankRepository, IdempotencyRecord, MovementPage, TransferOutcome, TransferPlanner } from './types.js';

const clone = <T>(v: T): T => structuredClone(v);

/**
 * In-memory adapter with the same semantics as the Firestore one. Each
 * operation reads, validates, then writes, so a thrown planner error leaves
 * state untouched — the same guarantee a Firestore transaction gives.
 */
export class MemoryBankRepository implements BankRepository {
  readonly customers = new Map<string, Customer>();
  readonly accounts = new Map<string, Map<string, Account>>();
  readonly movements = new Map<string, Movement[]>();
  readonly events = new Map<string, BehaviorEvent[]>();
  readonly devices = new Map<string, Map<string, Device>>();
  readonly experiences = new Map<string, Experience>();
  readonly idempotency = new Map<string, IdempotencyRecord>();
  readonly accountIndex = new Map<string, AccountRef>();

  async getCustomer(uid: string) {
    return clone(this.customers.get(uid) ?? null);
  }

  async createCustomer(customer: Customer, accounts: Account[], movements: Movement[]) {
    for (const a of accounts) {
      const taken = this.accountIndex.get(a.accountNumber);
      if (taken && taken.uid !== customer.uid) throw new Error(`account number taken: ${a.accountNumber}`);
    }
    for (const a of accounts) this.accountIndex.set(a.accountNumber, { uid: customer.uid, accountId: a.id });
    this.customers.set(customer.uid, clone(customer));
    this.accounts.set(customer.uid, new Map(accounts.map((a) => [a.id, clone(a)])));
    this.movements.set(customer.uid, clone(movements));
  }

  async updateInterests(uid: string, interests: Customer['preferences']['interests']) {
    const c = this.customers.get(uid);
    if (c) c.preferences = { ...c.preferences, interests: [...interests] };
  }

  async listAccounts(uid: string) {
    return [...(this.accounts.get(uid)?.values() ?? [])].map(clone);
  }

  async getAccount(uid: string, accountId: string) {
    return clone(this.accounts.get(uid)?.get(accountId) ?? null);
  }

  async listMovements(uid: string, accountId: string, limit: number, cursor?: string | null): Promise<MovementPage> {
    const all = (this.movements.get(uid) ?? [])
      .filter((m) => m.accountId === accountId)
      .sort((a, b) => b.date.localeCompare(a.date) || b.id.localeCompare(a.id));
    let start = 0;
    if (cursor) {
      const idx = all.findIndex((m) => m.id === cursor);
      if (idx < 0) throw new HttpError(400, 'invalid_request', 'Cursor inválido');
      start = idx + 1;
    }
    const items = all.slice(start, start + limit);
    const hasMore = start + limit < all.length;
    return { items: clone(items), nextCursor: hasMore ? (items.at(-1)?.id ?? null) : null };
  }

  async listMovementsSince(uid: string, sinceIso: string) {
    return clone((this.movements.get(uid) ?? []).filter((m) => m.date >= sinceIso));
  }

  async findAccountByNumber(accountNumber: string) {
    return clone(this.accountIndex.get(accountNumber) ?? null);
  }

  async executeTransfer(
    initiatorUid: string,
    idempotencyKey: string,
    requestHash: string,
    fromRef: AccountRef,
    toRef: AccountRef,
    plan: TransferPlanner,
  ): Promise<TransferOutcome> {
    const idemKey = `${initiatorUid}_${idempotencyKey}`;
    const existing = this.idempotency.get(idemKey);
    if (existing) {
      if (existing.requestHash !== requestHash) {
        throw new HttpError(409, 'idempotency_conflict', 'La clave de idempotencia ya se usó con otra solicitud');
      }
      return { result: clone(existing.body), replayed: true };
    }
    const from = this.accounts.get(fromRef.uid)?.get(fromRef.accountId);
    const to = this.accounts.get(toRef.uid)?.get(toRef.accountId);
    if (!from || !to) throw new HttpError(404, 'not_found', 'Cuenta no encontrada');

    const planned = plan(clone(from), clone(to)); // may throw -> nothing written

    this.accounts.get(fromRef.uid)!.set(planned.from.id, planned.from);
    this.accounts.get(toRef.uid)!.set(planned.to.id, planned.to);
    for (const m of planned.movements) {
      const owner = m.accountId === fromRef.accountId ? fromRef.uid : toRef.uid;
      this.movements.set(owner, [...(this.movements.get(owner) ?? []), clone(m)]);
    }
    this.idempotency.set(idemKey, { requestHash, body: clone(planned.result), createdAt: planned.result.createdAt });
    return { result: clone(planned.result), replayed: false };
  }

  async recordEvent(uid: string, event: BehaviorEvent) {
    this.events.set(uid, [...(this.events.get(uid) ?? []), clone(event)]);
  }

  async listEventsSince(uid: string, sinceIso: string) {
    return clone((this.events.get(uid) ?? []).filter((e) => e.at >= sinceIso));
  }

  async saveDevice(uid: string, token: string, platform: Platform) {
    const map = this.devices.get(uid) ?? new Map<string, Device>();
    map.set(token, { token, platform, updatedAt: new Date().toISOString() });
    this.devices.set(uid, map);
  }

  async listDevices(uid: string) {
    return [...(this.devices.get(uid)?.values() ?? [])].map(clone);
  }

  async removeDevices(uid: string, tokens: string[]) {
    const map = this.devices.get(uid);
    for (const t of tokens) map?.delete(t);
  }

  async listActiveExperiences() {
    return [...this.experiences.values()].filter((e) => e.active).map(clone);
  }

  async upsertExperience(experience: Experience) {
    this.experiences.set(experience.id, clone(experience));
  }
}
