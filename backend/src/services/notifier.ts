import type { Messaging } from 'firebase-admin/messaging';
import type { BankRepository } from '../repo/types.js';

export interface PushMessage {
  title: string;
  body: string;
  data?: Record<string, string>;
}

export interface PushReport {
  sent: number;
  failed: number;
  removedTokens: number;
}

export interface Notifier {
  sendToUser(uid: string, message: PushMessage): Promise<PushReport>;
}

/** FCM error codes meaning the token will never work again. */
const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);

/**
 * FCM multicast to every registered device of the user. Tokens FCM reports
 * as dead are pruned so the device list does not rot.
 */
export class FcmNotifier implements Notifier {
  constructor(
    private readonly messaging: Messaging,
    private readonly repo: BankRepository,
  ) {}

  async sendToUser(uid: string, message: PushMessage): Promise<PushReport> {
    const devices = await this.repo.listDevices(uid);
    if (devices.length === 0) return { sent: 0, failed: 0, removedTokens: 0 };

    const tokens = devices.map((d) => d.token);
    const response = await this.messaging.sendEachForMulticast({
      tokens,
      notification: { title: message.title, body: message.body },
      data: message.data,
      android: { priority: 'high', notification: { channelId: 'transactions' } },
      apns: { payload: { aps: { sound: 'default' } } },
    });

    const dead: string[] = [];
    response.responses.forEach((r, i) => {
      if (!r.success && r.error && DEAD_TOKEN_CODES.has(r.error.code)) dead.push(tokens[i]!);
    });
    await this.repo.removeDevices(uid, dead);
    return { sent: response.successCount, failed: response.failureCount, removedTokens: dead.length };
  }
}
