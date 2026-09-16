import { createCipheriv, createDecipheriv, createPublicKey, diffieHellman,
  generateKeyPairSync, hkdfSync, randomBytes, randomUUID, sign, type KeyObject } from 'node:crypto';
import { deviceId, envelopeAAD, signatureInput, type Envelope } from '../src/protocol.js';

// Test/reference client only: the relay never imports this module or receives private keys.
export class Client {
  readonly signing = generateKeyPairSync('ed25519');
  readonly encryption = generateKeyPairSync('x25519');
  readonly publicKey = this.signing.publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('hex');
  readonly encryptionKey = this.encryption.publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('hex');
  readonly id = deviceId(this.publicKey);
  invitation() { return { id: randomUUID(), token: randomBytes(32).toString('base64url'), encryptionKey: this.encryptionKey }; }
  headers(method: string, path: string, body = '', time = Date.now(), nonce = randomBytes(16).toString('hex')) {
    const timestamp = String(time);
    return { ...(body ? { 'content-type': 'application/json' } : {}), 'x-gatto-key': this.publicKey,
      'x-gatto-time': timestamp, 'x-gatto-nonce': nonce,
      'x-gatto-signature': sign(null, signatureInput(method, path, this.publicKey, timestamp, nonce, Buffer.from(body)), this.signing.privateKey).toString('hex') };
  }
  seal(peer: Client, pairingId: string, content: string, expiresAt = Date.now() + 60_000, id = randomUUID()): Envelope {
    const metadata = { version: 1 as const, id, pairingId, senderId: this.id,
      recipientId: peer.id, repositoryId: 'repo-one', expiresAt };
    const key = boxKey(this.encryption.privateKey, peer.encryptionKey, metadata);
    const nonce = randomBytes(12), cipher = createCipheriv('aes-256-gcm', key, nonce);
    cipher.setAAD(envelopeAAD(metadata));
    const ciphertext = Buffer.concat([cipher.update(content, 'utf8'), cipher.final()]);
    return { ...metadata, sealed: Buffer.concat([nonce, ciphertext, cipher.getAuthTag()]).toString('base64') };
  }
  open(peer: Client, envelope: Envelope): string {
    const key = boxKey(this.encryption.privateKey, peer.encryptionKey, envelope);
    const packed = Buffer.from(envelope.sealed, 'base64');
    const decipher = createDecipheriv('aes-256-gcm', key, packed.subarray(0, 12));
    decipher.setAAD(envelopeAAD(envelope)); decipher.setAuthTag(packed.subarray(-16));
    return Buffer.concat([decipher.update(packed.subarray(12, -16)), decipher.final()]).toString('utf8');
  }
}
function boxKey(privateKey: KeyObject, peer: string, e: Omit<Envelope, 'sealed'>): Buffer {
  const publicKey = createPublicKey({ format: 'der', type: 'spki', key: Buffer.concat([
    Buffer.from('302a300506032b656e032100', 'hex'), Buffer.from(peer, 'hex'),
  ]) });
  const secret = diffieHellman({ privateKey, publicKey });
  return Buffer.from(hkdfSync('sha256', secret, Buffer.from(e.pairingId, 'utf8'),
    Buffer.from(`GATTO-KEY/1\n${e.senderId}\n${e.recipientId}\n`), 32));
}
