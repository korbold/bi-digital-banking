import { cert, getApps, initializeApp, type App } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';

/**
 * Lazily initialises firebase-admin from FIREBASE_SERVICE_ACCOUNT (base64 of
 * the service-account JSON). Reused across warm invocations.
 */
export function firebaseApp(): App {
  const existing = getApps()[0];
  if (existing) return existing;
  const encoded = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!encoded) throw new Error('FIREBASE_SERVICE_ACCOUNT no está configurada');
  const credentials = JSON.parse(Buffer.from(encoded, 'base64').toString('utf8')) as {
    project_id: string;
    client_email: string;
    private_key: string;
  };
  return initializeApp({
    credential: cert({
      projectId: credentials.project_id,
      clientEmail: credentials.client_email,
      privateKey: credentials.private_key,
    }),
  });
}

export const firestore = () => getFirestore(firebaseApp());
export const firebaseAuth = () => getAuth(firebaseApp());
export const messaging = () => getMessaging(firebaseApp());
