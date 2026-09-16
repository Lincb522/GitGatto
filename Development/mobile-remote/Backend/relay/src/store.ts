import { DatabaseSync, type SQLInputValue } from 'node:sqlite';
import { deviceId, fail, sha256, type Envelope } from './protocol.js';

export interface Device { id: string; signingKey: string; encryptionKey: string; lastSeen: number }
export interface Pairing {
  id: string; hostId: string; mobileId: string | null;
  state: 'pending' | 'claimed' | 'approved' | 'revoked';
  expiresAt: number; repositories: string;
}
type Message = { senderId: string; recipientId: string; digest: string; acked: number };

export class RelayStore {
  private readonly db: DatabaseSync;
  constructor(path: string) {
    this.db = new DatabaseSync(path, { timeout: 1000 });
    this.db.exec(`PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL;
      PRAGMA synchronous=FULL; PRAGMA busy_timeout=1000; PRAGMA secure_delete=ON;
      PRAGMA max_page_count=131072;`);
    const version = this.db.prepare('PRAGMA user_version').get()?.user_version;
    if (version !== 0 && version !== 1) { this.db.close(); throw new Error('Unsupported relay database schema'); }
    this.db.exec(`BEGIN IMMEDIATE;
      CREATE TABLE IF NOT EXISTS devices (
        id TEXT PRIMARY KEY, signingKey TEXT NOT NULL, encryptionKey TEXT NOT NULL, lastSeen INTEGER NOT NULL DEFAULT 0
      ) STRICT;
      CREATE TABLE IF NOT EXISTS pairings (
        id TEXT PRIMARY KEY, tokenHash TEXT NOT NULL, hostId TEXT NOT NULL REFERENCES devices(id),
        mobileId TEXT REFERENCES devices(id), state TEXT NOT NULL, expiresAt INTEGER NOT NULL,
        repositories TEXT NOT NULL DEFAULT '[]', revokedAt INTEGER
      ) STRICT;
      CREATE INDEX IF NOT EXISTS pairing_host ON pairings(hostId, state);
      CREATE INDEX IF NOT EXISTS pairing_mobile ON pairings(mobileId, state);
      CREATE TABLE IF NOT EXISTS nonces (
        deviceId TEXT NOT NULL, nonce TEXT NOT NULL, expiresAt INTEGER NOT NULL,
        PRIMARY KEY(deviceId, nonce)
      ) STRICT;
      CREATE INDEX IF NOT EXISTS nonce_expiry ON nonces(expiresAt);
      CREATE TABLE IF NOT EXISTS messages (
        seq INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL, senderId TEXT NOT NULL,
        recipientId TEXT NOT NULL, pairingId TEXT NOT NULL REFERENCES pairings(id),
        digest TEXT NOT NULL, envelope TEXT, expiresAt INTEGER NOT NULL, acked INTEGER NOT NULL DEFAULT 0,
        UNIQUE(senderId, id)
      ) STRICT;
      CREATE INDEX IF NOT EXISTS message_recipient ON messages(recipientId, acked, seq);
      CREATE INDEX IF NOT EXISTS message_expiry ON messages(expiresAt);
      PRAGMA user_version=1; COMMIT;`);
  }
  close(): void { this.db.close(); }
  private run(sql: string, ...args: SQLInputValue[]) { return this.db.prepare(sql).run(...args); }
  private row<T>(sql: string, ...args: SQLInputValue[]): T | undefined {
    return this.db.prepare(sql).get(...args) as T | undefined;
  }
  private rows<T>(sql: string, ...args: SQLInputValue[]): T[] {
    return this.db.prepare(sql).all(...args) as unknown as T[];
  }
  private count(table: 'devices' | 'pairings' | 'messages' | 'nonces'): number {
    return Number(this.row<{ count: number }>(`SELECT count(*) AS count FROM ${table}`)?.count ?? 0);
  }
  private transaction<T>(fn: () => T): T {
    this.db.exec('BEGIN IMMEDIATE');
    try { const result = fn(); this.db.exec('COMMIT'); return result; }
    catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }
  cleanup(now: number): void {
    this.transaction(() => {
      this.run('DELETE FROM nonces WHERE expiresAt <= ?', now);
      this.run('UPDATE messages SET envelope=NULL, acked=1 WHERE expiresAt <= ? AND acked=0', now);
      // Retain delivery tombstones beyond the maximum message lifetime.
      this.run('DELETE FROM messages WHERE expiresAt < ?', now - 86_400_000);
      this.run("UPDATE pairings SET state='revoked', tokenHash='', revokedAt=? WHERE state IN ('pending','claimed') AND expiresAt<=?", now, now);
      this.run("DELETE FROM pairings WHERE state='revoked' AND revokedAt < ? AND NOT EXISTS (SELECT 1 FROM messages WHERE messages.pairingId=pairings.id)", now - 86_400_000);
      this.run('DELETE FROM devices WHERE NOT EXISTS (SELECT 1 FROM pairings WHERE hostId=devices.id OR mobileId=devices.id)');
    });
  }
  consumeNonce(id: string, nonce: string, expiresAt: number, now: number): void {
    this.transaction(() => {
      this.run('DELETE FROM nonces WHERE expiresAt<=?', now);
      if (this.row('SELECT 1 FROM nonces WHERE deviceId=? AND nonce=?', id, nonce)) fail(401, 'request_replayed');
      if (this.count('nonces') >= 30_000) fail(503, 'auth_capacity_reached');
      this.run('INSERT INTO nonces VALUES (?,?,?)', id, nonce, expiresAt);
    });
  }
  device(id: string): Device | undefined { return this.row<Device>('SELECT * FROM devices WHERE id=?', id); }
  private enroll(signingKey: string, encryptionKey: string): Device {
    const id = deviceId(signingKey), previous = this.device(id);
    if (previous) {
      if (previous.encryptionKey !== encryptionKey) fail(409, 'device_key_changed');
      return previous;
    }
    if (this.count('devices') >= 2000) fail(503, 'device_capacity_reached');
    this.run('INSERT INTO devices(id,signingKey,encryptionKey) VALUES (?,?,?)', id, signingKey, encryptionKey);
    return { id, signingKey, encryptionKey, lastSeen: 0 };
  }
  createPair(id: string, token: string, signingKey: string, encryptionKey: string, now: number) {
    return this.transaction(() => {
      const hostId = deviceId(signingKey);
      const prior = this.row<Pairing & { tokenHash: string }>('SELECT * FROM pairings WHERE id=?', id);
      if (prior) {
        if (prior.hostId !== hostId || prior.tokenHash !== sha256(token)
          || prior.expiresAt <= now || !['pending','claimed'].includes(prior.state)
          || this.device(hostId)?.encryptionKey !== encryptionKey) fail(409, 'pairing_id_conflict');
        return { id, expiresAt: prior.expiresAt, hostId };
      }
      if (this.count('pairings') >= 2000) fail(503, 'pairing_capacity_reached');
      const active = this.row<{ n: number }>("SELECT count(*) AS n FROM pairings WHERE hostId=? AND state != 'revoked'", hostId)?.n ?? 0;
      if (active >= 20) fail(409, 'host_pairing_limit');
      this.enroll(signingKey, encryptionKey);
      const expiresAt = now + 300_000;
      this.run('INSERT INTO pairings(id,tokenHash,hostId,state,expiresAt) VALUES (?,?,?,?,?)',
        id, sha256(token), hostId, 'pending', expiresAt);
      return { id, expiresAt, hostId };
    });
  }
  pairing(id: string): Pairing { return this.row<Pairing>('SELECT * FROM pairings WHERE id=?', id) ?? fail(404, 'pairing_not_found'); }
  claimPair(id: string, token: string, signingKey: string, encryptionKey: string, now: number) {
    return this.transaction(() => {
      const p = this.row<Pairing & { tokenHash: string }>('SELECT * FROM pairings WHERE id=?', id);
      if (!p || p.expiresAt <= now || p.tokenHash !== sha256(token)) fail(404, 'pairing_unavailable');
      const mobileId = deviceId(signingKey);
      if (mobileId === p.hostId) fail(409, 'distinct_devices_required');
      if (p.state !== 'pending' && !(p.state === 'claimed' && p.mobileId === mobileId)) fail(409, 'pairing_already_claimed');
      this.enroll(signingKey, encryptionKey);
      this.run("UPDATE pairings SET mobileId=?,state='claimed' WHERE id=?", mobileId, id);
      return { id, state: 'claimed', host: this.device(p.hostId), expiresAt: p.expiresAt };
    });
  }
  viewPair(id: string, caller: string) {
    const p = this.pairing(id);
    if (p.hostId !== caller && p.mobileId !== caller) fail(404, 'pairing_not_found');
    return { id: p.id, hostId: p.hostId, mobileId: p.mobileId, state: p.state, expiresAt: p.expiresAt,
      repositories: JSON.parse(p.repositories) as string[],
      host: this.device(p.hostId), mobile: p.mobileId ? this.device(p.mobileId) : null };
  }
  listPairs(caller: string) {
    return this.rows<{ id: string }>('SELECT id FROM pairings WHERE hostId=? OR mobileId=? ORDER BY id LIMIT 100', caller, caller)
      .map(p => this.viewPair(p.id, caller));
  }
  receipt(caller: string, id: string, now: number) {
    const row = this.row<{ pairingId: string; expiresAt: number; acked: number }>(
      'SELECT pairingId,expiresAt,acked FROM messages WHERE senderId=? AND id=?', caller, id);
    if (!row) fail(404, 'message_not_found');
    const p = this.pairing(row.pairingId);
    if (p.state !== 'approved') fail(403, 'pairing_not_authorized');
    return { id, state: row.expiresAt <= now ? 'expired' : row.acked ? 'acknowledged' : 'queued' };
  }
  seen(caller: string, now: number): void { this.run('UPDATE devices SET lastSeen=? WHERE id=?', now, caller); }
  approvePair(id: string, caller: string, mobileId: string, repositories: string[], now: number) {
    return this.transaction(() => {
      const p = this.pairing(id);
      if (p.hostId !== caller) fail(403, 'host_approval_required');
      if (p.mobileId !== mobileId) fail(409, 'pairing_identity_changed');
      const scopes = JSON.stringify(repositories);
      if (p.state === 'approved' && p.repositories === scopes) return this.viewPair(id, caller);
      if (p.state !== 'claimed' || p.expiresAt <= now) fail(409, 'pairing_not_approvable');
      this.run("UPDATE pairings SET state='approved',tokenHash='',repositories=? WHERE id=?", scopes, id);
      return this.viewPair(id, caller);
    });
  }
  revokePair(id: string, caller: string, now: number): Pairing {
    return this.transaction(() => {
      const p = this.pairing(id);
      if (p.hostId !== caller && p.mobileId !== caller) fail(404, 'pairing_not_found');
      this.run("UPDATE pairings SET state='revoked',tokenHash='',revokedAt=COALESCE(revokedAt,?) WHERE id=?", now, id);
      this.run('UPDATE messages SET acked=1,envelope=NULL WHERE pairingId=?', id);
      return p;
    });
  }
  activePairs(caller: string): Pairing[] {
    return this.rows<Pairing>("SELECT * FROM pairings WHERE (hostId=? OR mobileId=?) AND state='approved'", caller, caller);
  }
  requireActive(caller: string): void {
    if (!this.activePairs(caller).length) fail(403, 'device_not_paired');
  }
  send(e: Envelope, caller: string, now: number) {
    return this.transaction(() => {
      if (e.senderId !== caller) fail(403, 'sender_mismatch');
      const p = this.pairing(e.pairingId);
      const peer = p.hostId === caller ? p.mobileId : p.mobileId === caller ? p.hostId : null;
      if (p.state !== 'approved' || !peer || peer !== e.recipientId) fail(403, 'pairing_not_authorized');
      if (!(JSON.parse(p.repositories) as string[]).includes(e.repositoryId)) fail(403, 'repository_not_authorized');
      if (e.expiresAt <= now || e.expiresAt > now + 600_000) fail(400, 'invalid_message_expiry');
      const serialized = JSON.stringify(e), digest = sha256(serialized);
      const prior = this.row<Message>('SELECT * FROM messages WHERE senderId=? AND id=?', caller, e.id);
      if (prior) {
        if (prior.digest !== digest) fail(409, 'message_id_conflict');
        return { id: e.id, state: prior.acked ? 'acknowledged' : 'queued', duplicate: true };
      }
      const queued = this.row<{ n: number }>('SELECT count(*) AS n FROM messages WHERE pairingId=? AND acked=0', p.id)?.n ?? 0;
      const totalQueued = this.row<{ n: number }>('SELECT count(*) AS n FROM messages WHERE acked=0')?.n ?? 0;
      if (queued >= 128 || totalQueued >= 4096 || this.count('messages') >= 20_000) fail(429, 'queue_full');
      this.run('INSERT INTO messages(id,senderId,recipientId,pairingId,digest,envelope,expiresAt) VALUES (?,?,?,?,?,?,?)',
        e.id, caller, e.recipientId, p.id, digest, serialized, e.expiresAt);
      return { id: e.id, state: 'queued', duplicate: false };
    });
  }
  inbox(caller: string, now: number): Envelope[] {
    this.requireActive(caller);
    return this.rows<{ envelope: string }>(`SELECT m.envelope FROM messages m JOIN pairings p ON p.id=m.pairingId
      WHERE m.recipientId=? AND m.acked=0 AND m.expiresAt>? AND p.state='approved' ORDER BY m.seq LIMIT 32`, caller, now)
      .map(row => JSON.parse(row.envelope) as Envelope);
  }
  ack(caller: string, receipts: { senderId: string; id: string }[], now: number): number {
    this.requireActive(caller);
    return this.transaction(() => {
      let changed = 0;
      for (const receipt of receipts) changed += Number(this.run(`UPDATE messages SET acked=1,envelope=NULL
        WHERE id=? AND senderId=? AND recipientId=? AND expiresAt>? AND acked=0`, receipt.id, receipt.senderId, caller, now).changes);
      return changed;
    });
  }
}
