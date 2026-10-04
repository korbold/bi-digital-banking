/**
 * One-off migration for v1.1 (third-party transfers): gives every existing
 * account a full 10-digit `accountNumber` and registers it in
 * `accountIndex/{accountNumber}`. Idempotent: accounts that already have a
 * number are skipped. The last four digits are kept so the masked number
 * customers already know (****1234) does not change.
 *
 *   FIREBASE_SERVICE_ACCOUNT=<base64> npm run migrate:account-numbers
 */
import { randomInt } from 'node:crypto';
import { firestore } from '../src/infra/firebase.js';

const db = firestore();
let migrated = 0;
let skipped = 0;

for (const customer of (await db.collection('customers').get()).docs) {
  for (const account of (await customer.ref.collection('accounts').get()).docs) {
    const data = account.data();
    if (typeof data.accountNumber === 'string' && data.accountNumber.length === 10) {
      skipped++;
      continue;
    }
    const last4 = String(data.number ?? '').replace(/\D/g, '').slice(-4).padStart(4, '0');
    const prefix = data.type === 'checking' ? '10' : '22';
    for (let attempt = 0; ; attempt++) {
      const candidate = `${prefix}${String(randomInt(0, 10_000)).padStart(4, '0')}${last4}`;
      try {
        await db.runTransaction(async (tx) => {
          const indexRef = db.collection('accountIndex').doc(candidate);
          if ((await tx.get(indexRef)).exists) throw new Error('taken');
          tx.create(indexRef, { uid: customer.id, accountId: account.id });
          tx.update(account.ref, { accountNumber: candidate });
        });
        console.log(`${customer.id}/${account.id} -> ${candidate}`);
        migrated++;
        break;
      } catch (error) {
        if (attempt > 20) throw error;
      }
    }
  }
}
console.log(`migrated ${migrated}, already had a number ${skipped}`);
process.exit(0);
