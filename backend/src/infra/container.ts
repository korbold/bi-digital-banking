import { FirestoreBankRepository } from '../repo/firestore.js';
import type { BankRepository } from '../repo/types.js';
import { FxService } from '../services/fx.js';
import { FcmNotifier, type Notifier } from '../services/notifier.js';
import { firebaseAuth, firestore, messaging } from './firebase.js';

export interface TokenVerifier {
  verify(token: string): Promise<{ uid: string; email: string | null }>;
}

export interface Deps {
  repo: BankRepository;
  notifier: Notifier;
  fx: FxService;
  verifier: TokenVerifier;
}

let deps: Deps | null = null;

/** Composition root, memoised per warm instance. Tests call `setDeps`. */
export function getDeps(): Deps {
  if (deps) return deps;
  const repo = new FirestoreBankRepository(firestore());
  deps = {
    repo,
    notifier: new FcmNotifier(messaging(), repo),
    fx: new FxService({ apiUrl: process.env.FX_API_URL }),
    verifier: {
      async verify(token) {
        const decoded = await firebaseAuth().verifyIdToken(token);
        return { uid: decoded.uid, email: decoded.email ?? null };
      },
    },
  };
  return deps;
}

export function setDeps(next: Deps | null): void {
  deps = next;
}
