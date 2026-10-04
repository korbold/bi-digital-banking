import { createHash } from 'node:crypto';
import { HttpError, badRequest, unprocessable } from '../http.js';
import { cents } from '../rng.js';
import type { BankRepository, TransferOutcome, TransferPlanner } from '../repo/types.js';
import { maskAccountNumber } from '../domain/seed.js';
import type { AccountRef, BeneficiaryPreview, TransferInput } from '../types.js';
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
  const byId = typeof input.toAccountId === 'string' && input.toAccountId.length > 0;
  const byNumber = typeof input.toAccountNumber === 'string' && input.toAccountNumber.length > 0;
  if (byId === byNumber) throw badRequest('Envía exactamente uno de "toAccountId" o "toAccountNumber"');
  if (byNumber && !ACCOUNT_NUMBER.test(input.toAccountNumber!)) {
    throw badRequest('"toAccountNumber" debe tener 10 dígitos');
  }
  if (byId && input.fromAccountId === input.toAccountId) {
    throw unprocessable('same_account', 'La cuenta de origen y destino deben ser distintas');
  }
  const description = input.description.trim() || 'Transferencia';
  if (description.length > 60) throw badRequest('"description" admite máximo 60 caracteres');
  return { ...input, amount: cents(amount), description };
}

export const ACCOUNT_NUMBER = /^\d{10}$/;

/** Stable hash of the request so a reused key with a different payload is rejected. */
export function hashTransfer(input: TransferInput): string {
  return createHash('sha256')
    .update(
      JSON.stringify([input.fromAccountId, input.toAccountId ?? null, input.toAccountNumber ?? null, input.amount, input.description]),
    )
    .digest('hex');
}

/** "Danny Barahona" -> "Danny B." — enough to confirm a recipient, not to identify them. */
export function maskHolderName(name: string): string {
  const [first = '', ...rest] = name.trim().split(/\s+/);
  const initial = rest.find((p) => p.length > 0)?.[0];
  return initial ? `${first} ${initial.toUpperCase()}.` : first;
}

const defaultId = (prefix: string) => `${prefix}_${crypto.randomUUID().replaceAll('-', '').slice(0, 20)}`;

/** Resolves a 10-digit account number for the beneficiary preview. */
export async function lookupBeneficiary(uid: string, accountNumber: string, repo: BankRepository): Promise<BeneficiaryPreview> {
  if (!ACCOUNT_NUMBER.test(accountNumber)) throw badRequest('El número de cuenta debe tener 10 dígitos');
  const ref = await repo.findAccountByNumber(accountNumber);
  const [account, holder] = ref
    ? await Promise.all([repo.getAccount(ref.uid, ref.accountId), repo.getCustomer(ref.uid)])
    : [null, null];
  if (!ref || !account || !holder) {
    throw new HttpError(404, 'beneficiary_not_found', 'No encontramos una cuenta con ese número');
  }
  const isOwn = ref.uid === uid;
  return {
    accountNumber,
    maskedNumber: maskAccountNumber(accountNumber),
    holderName: maskHolderName(holder.name),
    type: account.type,
    isOwn,
    accountId: isOwn ? ref.accountId : null,
  };
}

/**
 * Transfer to an own account (by id) or to any account (by number). Debit
 * and credit happen in one repository transaction even across customers;
 * push notifications are best-effort and never fail the transfer (the money
 * already moved).
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

  const from: AccountRef = { uid, accountId: input.fromAccountId };
  let to: AccountRef;
  if (input.toAccountNumber) {
    const found = await deps.repo.findAccountByNumber(input.toAccountNumber);
    if (!found) throw new HttpError(404, 'beneficiary_not_found', 'No encontramos una cuenta con ese número');
    to = found;
  } else {
    to = { uid, accountId: input.toAccountId! };
  }
  if (to.uid === from.uid && to.accountId === from.accountId) {
    throw unprocessable('same_account', 'La cuenta de origen y destino deben ser distintas');
  }
  const thirdParty = to.uid !== uid;
  const [sender, recipient] = thirdParty
    ? await Promise.all([deps.repo.getCustomer(uid), deps.repo.getCustomer(to.uid)])
    : [null, null];
  const senderName = maskHolderName(sender?.name ?? 'Cliente');
  const recipientName = maskHolderName(recipient?.name ?? 'Cliente');

  const plan: TransferPlanner = (fromAccount, toAccount) => {
    if (fromAccount.available < input.amount) {
      throw new HttpError(422, 'insufficient_funds', 'Saldo insuficiente en la cuenta de origen');
    }
    const at = now().toISOString();
    const transferId = newId('trf');
    const fromBalance = cents(fromAccount.balance - input.amount);
    const toBalance = cents(toAccount.balance + input.amount);
    const debitLabel = thirdParty ? `a ${recipientName} ${toAccount.number}` : `a ${toAccount.alias}`;
    const creditLabel = thirdParty ? `de ${senderName}` : `desde ${fromAccount.alias}`;
    return {
      from: { ...fromAccount, balance: fromBalance, available: cents(fromAccount.available - input.amount) },
      to: { ...toAccount, balance: toBalance, available: cents(toAccount.available + input.amount) },
      movements: [
        {
          id: newId('mov'),
          accountId: fromAccount.id,
          date: at,
          description: `${input.description} · ${debitLabel}`,
          amount: -input.amount,
          category: 'transfer',
          balanceAfter: fromBalance,
          transferId,
        },
        {
          id: newId('mov'),
          accountId: toAccount.id,
          date: at,
          description: `${input.description} · ${creditLabel}`,
          amount: input.amount,
          category: 'transfer',
          balanceAfter: toBalance,
          transferId,
        },
      ],
      result: thirdParty
        ? {
            transferId,
            kind: 'third_party',
            from: { id: fromAccount.id, balance: fromBalance },
            to: { accountNumber: toAccount.number, holderName: recipientName },
            createdAt: at,
          }
        : {
            transferId,
            kind: 'own',
            from: { id: fromAccount.id, balance: fromBalance },
            to: { id: toAccount.id, balance: toBalance },
            createdAt: at,
          },
    };
  };

  const outcome = await deps.repo.executeTransfer(uid, idempotencyKey, hashTransfer(input), from, to, plan);

  if (!outcome.replayed && deps.notifier) {
    const notifier = deps.notifier;
    const amount = `$${input.amount.toFixed(2)}`;
    const warn = (error: unknown) => deps.log?.({ level: 'warn', msg: 'push_failed', error: String(error) });
    const toAlias = thirdParty ? recipientName : ((await deps.repo.getAccount(uid, to.accountId))?.alias ?? 'tu cuenta');
    notifier
      .sendToUser(uid, {
        title: 'Transferencia realizada',
        body: `Enviaste ${amount} a ${toAlias}`,
        data: { type: 'transfer', route: `/accounts/${from.accountId}` },
      })
      .catch(warn);
    if (thirdParty) {
      notifier
        .sendToUser(to.uid, {
          title: 'Recibiste una transferencia',
          body: `${senderName} te envió ${amount}`,
          data: { type: 'transfer_received', route: `/accounts/${to.accountId}` },
        })
        .catch(warn);
    }
  }
  return outcome;
}
