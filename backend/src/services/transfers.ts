import { createHash } from 'node:crypto';
import { HttpError, badRequest, unprocessable } from '../http.js';
import { cents } from '../rng.js';
import type { BankRepository, TransferOutcome, TransferPlanner } from '../repo/types.js';
import type { TransferInput } from '../types.js';
import type { Notifier } from './notifier.js';

export const MAX_TRANSFER = 10_000;

export interface TransferDeps {
  repo: BankRepository;
  notifier?: Notifier;
  now?: () => Date;
  newId?: (prefix: string) => string;
  log?: (entry: Record<string, unknown>) => void;
}

/** Validates shape and business rules that do not need balances. */
export function validateTransferInput(input: TransferInput): TransferInput {
  const amount = input.amount;
  if (!Number.isFinite(amount) || amount <= 0) throw unprocessable('invalid_amount', 'El monto debe ser mayor a cero');
  if (cents(amount) !== amount) {
    throw unprocessable('invalid_amount', 'El monto admite máximo dos decimales');
  }
  if (amount > MAX_TRANSFER) throw unprocessable('invalid_amount', `El monto máximo por transferencia es $${MAX_TRANSFER}`);
  if (input.fromAccountId === input.toAccountId) {
    throw unprocessable('same_account', 'La cuenta de origen y destino deben ser distintas');
  }
  const description = input.description.trim() || 'Transferencia entre cuentas';
  if (description.length > 60) throw badRequest('"description" admite máximo 60 caracteres');
  return { ...input, amount: cents(amount), description };
}

/** Stable hash of the request so a reused key with a different payload is rejected. */
export function hashTransfer(input: TransferInput): string {
  return createHash('sha256')
    .update(JSON.stringify([input.fromAccountId, input.toAccountId, input.amount, input.description]))
    .digest('hex');
}

const defaultId = (prefix: string) => `${prefix}_${crypto.randomUUID().replaceAll('-', '').slice(0, 20)}`;

/**
 * Own-account transfer. Debit and credit happen in one repository
 * transaction; the push notification is best-effort and never fails the
 * transfer (the money already moved).
 */
export async function transfer(
  uid: string,
  idempotencyKey: string | null,
  raw: TransferInput,
  deps: TransferDeps,
): Promise<TransferOutcome> {
  if (!idempotencyKey || idempotencyKey.length < 8 || idempotencyKey.length > 100) {
    throw badRequest('Header Idempotency-Key obligatorio (8-100 caracteres)');
  }
  const input = validateTransferInput(raw);
  const now = deps.now ?? (() => new Date());
  const newId = deps.newId ?? defaultId;

  const plan: TransferPlanner = (from, to) => {
    if (from.available < input.amount) {
      throw new HttpError(422, 'insufficient_funds', 'Saldo insuficiente en la cuenta de origen');
    }
    const at = now().toISOString();
    const transferId = newId('trf');
    const fromBalance = cents(from.balance - input.amount);
    const toBalance = cents(to.balance + input.amount);
    return {
      from: { ...from, balance: fromBalance, available: cents(from.available - input.amount) },
      to: { ...to, balance: toBalance, available: cents(to.available + input.amount) },
      movements: [
        {
          id: newId('mov'),
          accountId: from.id,
          date: at,
          description: `${input.description} · a ${to.alias}`,
          amount: -input.amount,
          category: 'transfer',
          balanceAfter: fromBalance,
          transferId,
        },
        {
          id: newId('mov'),
          accountId: to.id,
          date: at,
          description: `${input.description} · desde ${from.alias}`,
          amount: input.amount,
          category: 'transfer',
          balanceAfter: toBalance,
          transferId,
        },
      ],
      result: {
        transferId,
        from: { id: from.id, balance: fromBalance },
        to: { id: to.id, balance: toBalance },
        createdAt: at,
      },
    };
  };

  const outcome = await deps.repo.executeTransfer(
    uid,
    idempotencyKey,
    hashTransfer(input),
    input.fromAccountId,
    input.toAccountId,
    plan,
  );

  if (!outcome.replayed && deps.notifier) {
    const toAccount = await deps.repo.getAccount(uid, input.toAccountId);
    deps.notifier
      .sendToUser(uid, {
        title: 'Transferencia realizada',
        body: `Enviaste $${input.amount.toFixed(2)} a ${toAccount?.alias ?? 'tu cuenta'}`,
        data: { type: 'transfer', route: `/accounts/${input.fromAccountId}` },
      })
      .catch((error: unknown) => deps.log?.({ level: 'warn', msg: 'push_failed', error: String(error) }));
  }
  return outcome;
}
