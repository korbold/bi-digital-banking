import type { DocumentData, Firestore } from 'firebase-admin/firestore';
import { HttpError } from '../http.js';
import type { Account, AccountRef, BehaviorEvent, Customer, Device, Experience, Movement, Platform } from '../types.js';
import type { BankRepository, IdempotencyRecord, MovementPage, TransferOutcome, TransferPlanner } from './types.js';

/**
 * Firestore adapter. Layout (see docs/api-contract.md):
 *   customers/{uid}
 *   customers/{uid}/accounts/{accountId}
 *   customers/{uid}/accounts/{accountId}/movements/{movementId}
 *   customers/{uid}/devices/{token}
 *   customers/{uid}/events/{eventId}
 *   experiences/{experienceId}
 *   idempotency/{uid}_{key}
 *   accountIndex/{accountNumber}       -> { uid, accountId }
 *
 * Dates are stored as ISO-8601 strings: they sort lexicographically, so
 * range queries and ordering work without Timestamp conversions.
 */
export class FirestoreBankRepository implements BankRepository {
  constructor(private readonly db: Firestore) {}

  private customer(uid: string) {
    return this.db.collection('customers').doc(uid);
  }

  private accountsCol(uid: string) {
    return this.customer(uid).collection('accounts');
  }

  private movementsCol(uid: string, accountId: string) {
    return this.accountsCol(uid).doc(accountId).collection('movements');
  }

  async getCustomer(uid: string): Promise<Customer | null> {
    const snap = await this.customer(uid).get();
    return snap.exists ? ({ uid, ...snap.data() } as Customer) : null;
  }

  async createCustomer(customer: Customer, accounts: Account[], movements: Movement[]): Promise<void> {
    const batch = this.db.batch();
    const { uid, ...data } = customer;
    batch.set(this.customer(uid), data);
    for (const { id, ...a } of accounts) {
      batch.set(this.accountsCol(uid).doc(id), a);
      // create() fails the whole batch if the number is already taken.
      batch.create(this.db.collection('accountIndex').doc(a.accountNumber), { uid, accountId: id });
    }
    for (const { id, ...m } of movements) batch.set(this.movementsCol(uid, m.accountId).doc(id), m);
    await batch.commit();
  }

  async updateInterests(uid: string, interests: Customer['preferences']['interests']): Promise<void> {
    await this.customer(uid).update({ 'preferences.interests': interests });
  }

  async listAccounts(uid: string): Promise<Account[]> {
    const snap = await this.accountsCol(uid).orderBy('createdAt').get();
    return snap.docs.map((d) => ({ id: d.id, ...d.data() }) as Account);
  }

  async getAccount(uid: string, accountId: string): Promise<Account | null> {
    const snap = await this.accountsCol(uid).doc(accountId).get();
    return snap.exists ? ({ id: snap.id, ...snap.data() } as Account) : null;
  }

  async listMovements(uid: string, accountId: string, limit: number, cursor?: string | null): Promise<MovementPage> {
    const col = this.movementsCol(uid, accountId);
    let query = col.orderBy('date', 'desc').limit(limit + 1);
    if (cursor) {
      const cursorSnap = await col.doc(cursor).get();
      if (!cursorSnap.exists) throw new HttpError(400, 'invalid_request', 'Cursor inválido');
      query = query.startAfter(cursorSnap);
    }
    const snap = await query.get();
    const docs = snap.docs.slice(0, limit);
    const items = docs.map((d) => ({ id: d.id, ...d.data() }) as Movement);
    return { items, nextCursor: snap.docs.length > limit ? (items.at(-1)?.id ?? null) : null };
  }

  async listMovementsSince(uid: string, sinceIso: string): Promise<Movement[]> {
    const accounts = await this.accountsCol(uid).get();
    const pages = await Promise.all(
      accounts.docs.map((a) => this.movementsCol(uid, a.id).where('date', '>=', sinceIso).get()),
    );
    return pages.flatMap((p) => p.docs.map((d) => ({ id: d.id, ...d.data() }) as Movement));
  }

  async findAccountByNumber(accountNumber: string): Promise<AccountRef | null> {
    const snap = await this.db.collection('accountIndex').doc(accountNumber).get();
    return snap.exists ? (snap.data() as AccountRef) : null;
  }

  async executeTransfer(
    initiatorUid: string,
    idempotencyKey: string,
    requestHash: string,
    from: AccountRef,
    to: AccountRef,
    plan: TransferPlanner,
  ): Promise<TransferOutcome> {
    const idemRef = this.db.collection('idempotency').doc(`${initiatorUid}_${idempotencyKey}`);
    const fromRef = this.accountsCol(from.uid).doc(from.accountId);
    const toRef = this.accountsCol(to.uid).doc(to.accountId);

    return this.db.runTransaction(async (tx) => {
      // All reads first (Firestore transaction rule), then all writes.
      const [idemSnap, fromSnap, toSnap] = await Promise.all([tx.get(idemRef), tx.get(fromRef), tx.get(toRef)]);

      if (idemSnap.exists) {
        const record = idemSnap.data() as IdempotencyRecord;
        if (record.requestHash !== requestHash) {
          throw new HttpError(409, 'idempotency_conflict', 'La clave de idempotencia ya se usó con otra solicitud');
        }
        return { result: record.body, replayed: true };
      }
      if (!fromSnap.exists || !toSnap.exists) throw new HttpError(404, 'not_found', 'Cuenta no encontrada');

      const planned = plan(
        { id: fromSnap.id, ...fromSnap.data() } as Account,
        { id: toSnap.id, ...toSnap.data() } as Account,
      );

      tx.update(fromRef, { balance: planned.from.balance, available: planned.from.available });
      tx.update(toRef, { balance: planned.to.balance, available: planned.to.available });
      for (const { id, ...m } of planned.movements) {
        const owner = m.accountId === from.accountId ? from.uid : to.uid;
        tx.set(this.movementsCol(owner, m.accountId).doc(id), m);
      }
      const record: IdempotencyRecord = { requestHash, body: planned.result, createdAt: planned.result.createdAt };
      tx.set(idemRef, record as unknown as DocumentData);
      return { result: planned.result, replayed: false };
    });
  }

  async recordEvent(uid: string, event: BehaviorEvent): Promise<void> {
    await this.customer(uid).collection('events').add(event);
  }

  async listEventsSince(uid: string, sinceIso: string): Promise<BehaviorEvent[]> {
    const snap = await this.customer(uid).collection('events').where('at', '>=', sinceIso).limit(500).get();
    return snap.docs.map((d) => d.data() as BehaviorEvent);
  }

  async saveDevice(uid: string, token: string, platform: Platform): Promise<void> {
    await this.customer(uid).collection('devices').doc(token).set({ platform, updatedAt: new Date().toISOString() });
  }

  async listDevices(uid: string): Promise<Device[]> {
    const snap = await this.customer(uid).collection('devices').get();
    return snap.docs.map((d) => ({ token: d.id, ...d.data() }) as Device);
  }

  async removeDevices(uid: string, tokens: string[]): Promise<void> {
    if (tokens.length === 0) return;
    const batch = this.db.batch();
    for (const t of tokens) batch.delete(this.customer(uid).collection('devices').doc(t));
    await batch.commit();
  }

  async listActiveExperiences(): Promise<Experience[]> {
    const snap = await this.db.collection('experiences').where('active', '==', true).get();
    return snap.docs.map((d) => ({ ...(d.data() as Experience), id: d.id }));
  }

  async upsertExperience(experience: Experience): Promise<void> {
    const { id, ...data } = experience;
    await this.db.collection('experiences').doc(id).set(data);
  }
}
