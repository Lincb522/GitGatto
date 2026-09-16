import { createHash, createPublicKey, verify } from 'node:crypto';
import { z } from 'zod';

export const keySchema = z.string().regex(/^[a-f0-9]{64}$/);
export const idSchema = z.string().uuid();
export const repositorySchema = z.string().regex(/^[a-zA-Z0-9_-]{1,80}$/);
export const tokenSchema = z.string().regex(/^[A-Za-z0-9_-]{43}$/);
export const createPairSchema = z.object({ id: idSchema, token: tokenSchema, encryptionKey: keySchema }).strict();
export const claimPairSchema = z.object({
  token: tokenSchema, encryptionKey: keySchema,
}).strict();
export const approvePairSchema = z.object({
  mobileId: keySchema,
  repositories: z.array(repositorySchema).min(1).max(100)
    .refine(v => new Set(v).size === v.length),
}).strict();
export const envelopeSchema = z.object({
  version: z.literal(1), id: idSchema, pairingId: idSchema,
  senderId: keySchema, recipientId: keySchema, repositoryId: repositorySchema,
  expiresAt: z.number().int().safe(),
  sealed: z.string().min(40).max(87_384).regex(/^[A-Za-z0-9+/]+={0,2}$/)
    .refine(v => Buffer.from(v, 'base64').toString('base64') === v
      && Buffer.from(v, 'base64').length >= 29 && Buffer.from(v, 'base64').length <= 65_536),
}).strict();
export type Envelope = z.infer<typeof envelopeSchema>;
export const ackSchema = z.object({ receipts: z.array(z.object({
  senderId: keySchema, id: idSchema,
}).strict()).min(1).max(50) }).strict();

export class RelayError extends Error {
  constructor(readonly status: number, readonly code: string) { super(code); }
}
export function fail(status: number, code: string): never { throw new RelayError(status, code); }
export function sha256(value: string | Buffer): string {
  return createHash('sha256').update(value).digest('hex');
}
export function deviceId(publicKey: string): string {
  return sha256(Buffer.from(publicKey, 'hex'));
}
export function signatureInput(method: string, path: string, publicKey: string,
  timestamp: string, nonce: string, body: Buffer): Buffer {
  return Buffer.from(['GATTO/1', method, path, publicKey, timestamp, nonce, sha256(body), ''].join('\n'));
}
export function verifySignature(publicKey: string, signature: string, message: Buffer): boolean {
  try {
    const key = createPublicKey({ key: Buffer.concat([
      Buffer.from('302a300506032b6570032100', 'hex'), Buffer.from(publicKey, 'hex'),
    ]), format: 'der', type: 'spki' });
    return verify(null, message, key, Buffer.from(signature, 'hex'));
  } catch { return false; }
}

// Stable UTF-8 AAD; the clients authenticate routing metadata, not just ciphertext.
export function envelopeAAD(e: Omit<Envelope, 'sealed'>): Buffer {
  return Buffer.from(['GATTO-BOX/1', e.id, e.pairingId, e.senderId, e.recipientId,
    e.repositoryId, String(e.expiresAt), ''].join('\n'));
}
