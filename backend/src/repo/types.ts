import type {
  Account,
  AccountRef,
  BehaviorEvent,
  Customer,
  Device,
  Experience,
  Movement,
  Platform,
  TransferResult,
} from '../types.js';

export interface MovementPage {
  items: Movement[];
  nextCursor: string | null;
}

/** Stored outcome of an idempotent request. */
export interface IdempotencyRecord {
  requestHash: string;
  body: TransferResult;
  createdAt: string;
}

/**
 * Pure transfer computation executed *inside* the repository's transaction,
 * after it has read fresh balances. Throws HttpError on business violations.
 */
export type TransferPlanner = (from: Account, to: Account) => {
  from: Account;
  to: Account;
  movements: Movement[];
  result: TransferResult;
};

export interface TransferOutcome {
  result: TransferResult;
  replayed: boolean;
}

/**
 * Persistence port. The Firestore adapter is used in production, the
 * in-memory adapter in unit tests; services depend only on this interface.
 */
export interface BankRepository {
  getCustomer(uid: string): Promise<Customer | null>;
  /** Creates customer + accounts + movements atomically. */
  createCustomer(customer: Customer, accounts: Account[], movements: Movement[]): Promise<void>;
  updateInterests(uid: string, interests: Customer['preferences']['interests']): Promise<void>;

  listAccounts(uid: string): Promise<Account[]>;
  getAccount(uid: string, accountId: string): Promise<Account | null>;
  /** Newest first. Cursor is the id of the last movement of the previous page. */
  listMovements(uid: string, accountId: string, limit: number, cursor?: string | null): Promise<MovementPage>;
  /** All accounts, movements with date >= sinceIso. */
  listMovementsSince(uid: string, sinceIso: string): Promise<Movement[]>;

  /** O(1) lookup through accountIndex/{accountNumber}. */
  findAccountByNumber(accountNumber: string): Promise<AccountRef | null>;

  /**
   * Atomically: check idempotency key (scoped to the initiating customer),
   * read both accounts — which may belong to different customers — run
   * `plan`, write new balances + movements + idempotency record. A replay
   * with the same key and request hash returns the stored result.
   */
  executeTransfer(
    initiatorUid: string,
    idempotencyKey: string,
    requestHash: string,
    from: AccountRef,
    to: AccountRef,
    plan: TransferPlanner,
  ): Promise<TransferOutcome>;

  recordEvent(uid: string, event: BehaviorEvent): Promise<void>;
  listEventsSince(uid: string, sinceIso: string): Promise<BehaviorEvent[]>;

  saveDevice(uid: string, token: string, platform: Platform): Promise<void>;
  listDevices(uid: string): Promise<Device[]>;
  removeDevices(uid: string, tokens: string[]): Promise<void>;

  listActiveExperiences(): Promise<Experience[]>;
  upsertExperience(experience: Experience): Promise<void>;
}
