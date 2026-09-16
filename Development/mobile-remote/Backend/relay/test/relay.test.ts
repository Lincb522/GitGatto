import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { test, type TestContext } from 'node:test';
import { WebSocket } from 'ws';
import { buildRelay } from '../src/server.js';
import { Client } from './client.js';
import type { Envelope } from '../src/protocol.js';

async function fixture(t: TestContext, options: { requestLimit?: number; heartbeatMs?: number } = {}) {
  const directory = mkdtempSync(join(tmpdir(), 'gatto-relay-test-'));
  const host = new Client(), mobile = new Client(), stranger = new Client();
  const clock = { value: Date.now() };
  const settings = { databasePath: join(directory, 'relay.sqlite'), allowedHostKeys: new Set([host.publicKey]),
    now: () => clock.value, ...options };
  let app = await buildRelay(settings);
  t.after(async () => { await app.close(); rmSync(directory, { recursive: true, force: true }); });
  async function request(client: Client, method: 'GET' | 'POST' | 'DELETE', path: string, body?: unknown) {
    const payload = body === undefined ? '' : JSON.stringify(body);
    return app.inject({ method, url: path, headers: client.headers(method, path, payload, clock.value),
      ...(payload ? { payload } : {}) });
  }
  async function pair() {
    const intent = host.invitation();
    const created = await request(host, 'POST', '/v1/pairings', intent);
    assert.equal(created.statusCode, 200, created.body);
    const invitation = { ...created.json(), token: intent.token };
    const claimed = await request(mobile, 'POST', `/v1/pairings/${invitation.id}/claim`,
      { token: invitation.token, encryptionKey: mobile.encryptionKey });
    assert.equal(claimed.statusCode, 200, claimed.body);
    const approved = await request(host, 'POST', `/v1/pairings/${invitation.id}/approve`,
      { mobileId: mobile.id, repositories: ['repo-one'] });
    assert.equal(approved.statusCode, 200, approved.body);
    return invitation.id as string;
  }
  return { host, mobile, stranger, clock, directory, settings, request, pair,
    get app() { return app; },
    async restart() { await app.close(); app = await buildRelay(settings); },
  };
}

test('pairing requires enrolled host, token possession and exact host approval', async t => {
  const f = await fixture(t);
  assert.equal((await f.request(f.stranger, 'POST', '/v1/pairings', f.stranger.invitation())).statusCode, 403);
  const intent = f.host.invitation();
  const invitation = { ...(await f.request(f.host, 'POST', '/v1/pairings', intent)).json(), token: intent.token };
  const path = `/v1/pairings/${invitation.id}`;
  assert.equal((await f.request(f.mobile, 'POST', path + '/claim', { token: 'a'.repeat(43), encryptionKey: f.mobile.encryptionKey })).statusCode, 404);
  assert.equal((await f.request(f.mobile, 'POST', path + '/claim', { token: invitation.token, encryptionKey: f.mobile.encryptionKey })).statusCode, 200);
  assert.equal((await f.request(f.mobile, 'GET', '/v1/messages')).statusCode, 403);
  assert.equal((await f.request(f.mobile, 'POST', path + '/approve', { mobileId: f.mobile.id, repositories: ['repo-one'] })).statusCode, 403);
  assert.equal((await f.request(f.host, 'POST', path + '/approve', { mobileId: f.stranger.id, repositories: ['repo-one'] })).statusCode, 409);
  const approved = await f.request(f.host, 'POST', path + '/approve', { mobileId: f.mobile.id, repositories: ['repo-one'] });
  assert.equal(approved.statusCode, 200);
  assert.equal(approved.json().mobile.encryptionKey, f.mobile.encryptionKey);
  assert.equal('tokenHash' in approved.json(), false);
  assert.equal((await f.request(f.stranger, 'GET', path)).statusCode, 404);
});

test('pair token expires, cannot be taken over, and device encryption key cannot silently rotate', async t => {
  const f = await fixture(t);
  const intent = f.host.invitation();
  const p = { ...(await f.request(f.host, 'POST', '/v1/pairings', intent)).json(), token: intent.token };
  assert.equal((await f.request(f.host, 'POST', '/v1/pairings', intent)).json().id, p.id);
  const path = `/v1/pairings/${p.id}/claim`;
  const body = { token: p.token, encryptionKey: f.mobile.encryptionKey };
  assert.equal((await f.request(f.mobile, 'POST', path, body)).statusCode, 200);
  assert.equal((await f.request(f.mobile, 'POST', path, body)).statusCode, 200);
  assert.equal((await f.request(f.stranger, 'POST', path, { ...body, encryptionKey: f.stranger.encryptionKey })).statusCode, 409);
  assert.equal((await f.request(f.host, 'POST', '/v1/pairings', { ...f.host.invitation(), encryptionKey: f.stranger.encryptionKey })).statusCode, 409);
  f.clock.value += 300_001;
  assert.equal((await f.request(f.mobile, 'POST', path, body)).statusCode, 404);
  assert.equal((await f.request(f.host, 'POST', `/v1/pairings/${p.id}/approve`, { mobileId: f.mobile.id, repositories: ['repo-one'] })).statusCode, 409);
});

test('signatures bind exact bytes, URL, method and time; nonces survive restart', async t => {
  const f = await fixture(t);
  const body = JSON.stringify(f.host.invitation());
  const headers = f.host.headers('POST', '/v1/pairings', body, f.clock.value);
  assert.equal((await f.app.inject({ method: 'POST', url: '/v1/pairings', headers, payload: body + ' ' })).statusCode, 401);
  assert.equal((await f.app.inject({ method: 'POST', url: '/v1/pairings', headers, payload: body })).statusCode, 200);
  await f.restart();
  assert.equal((await f.app.inject({ method: 'POST', url: '/v1/pairings', headers, payload: body })).json().error, 'request_replayed');
  assert.equal((await f.app.inject({ method: 'GET', url: '/v1/devices', headers })).statusCode, 401);
  assert.equal((await f.app.inject({ method: 'POST', url: '/v1/pairings', headers: f.host.headers('POST', '/v1/pairings', body, f.clock.value - 61_000), payload: body })).json().error, 'request_expired');
  assert.equal((await f.app.inject({ method: 'GET', url: '/v1/messages' })).statusCode, 401);
});

test('offline encrypted delivery survives restart; duplicate send and ack are idempotent', async t => {
  const f = await fixture(t), pair = await f.pair();
  const plaintext = 'private fixture command: inspect only, do not execute';
  const e = f.mobile.seal(f.host, pair, plaintext, f.clock.value + 60_000);
  const sent = await f.request(f.mobile, 'POST', '/v1/messages', e);
  assert.equal(sent.statusCode, 200, sent.body);
  assert.equal(sent.json().state, 'queued');
  assert.equal((await f.request(f.mobile, 'POST', '/v1/messages', e)).json().duplicate, true);
  await f.restart();
  const inbox = (await f.request(f.host, 'GET', '/v1/messages')).json().messages as Envelope[];
  assert.equal(inbox.length, 1);
  assert.equal(f.host.open(f.mobile, inbox[0]!), plaintext);
  assert.equal((await f.request(f.mobile, 'GET', '/v1/messages')).json().messages.length, 0);
  for (const file of readdirSync(f.directory)) assert.equal(readFileSync(join(f.directory, file)).includes(Buffer.from(plaintext)), false);
  const receipts = [{ senderId: f.mobile.id, id: e.id }];
  assert.equal((await f.request(f.mobile, 'POST', '/v1/messages/ack', { receipts })).json().acknowledged, 0);
  assert.equal((await f.request(f.host, 'POST', '/v1/messages/ack', { receipts })).json().acknowledged, 1);
  assert.equal((await f.request(f.host, 'POST', '/v1/messages/ack', { receipts })).json().acknowledged, 0);
  await f.restart();
  assert.equal((await f.request(f.host, 'GET', '/v1/messages')).json().messages.length, 0);
  assert.equal((await f.request(f.mobile, 'POST', '/v1/messages', e)).json().state, 'acknowledged');
});

test('routing isolates device, pairing and repository; ciphertext authenticates metadata', async t => {
  const f = await fixture(t), pair = await f.pair();
  const e = f.mobile.seal(f.host, pair, 'fixture', f.clock.value + 60_000);
  assert.equal((await f.request(f.mobile, 'POST', '/v1/messages', { ...e, senderId: f.host.id })).statusCode, 403);
  assert.equal((await f.request(f.mobile, 'POST', '/v1/messages', { ...e, recipientId: f.stranger.id })).statusCode, 403);
  assert.equal((await f.request(f.mobile, 'POST', '/v1/messages', { ...e, repositoryId: 'not-granted' })).statusCode, 403);
  assert.equal((await f.request(f.stranger, 'POST', '/v1/messages', { ...e, senderId: f.stranger.id })).statusCode, 403);
  assert.throws(() => f.host.open(f.mobile, { ...e, repositoryId: 'different' }));
  assert.throws(() => f.host.open(f.mobile, { ...e, sealed: Buffer.alloc(40).toString('base64') }));
  assert.equal((await f.request(f.mobile, 'POST', '/v1/messages', e)).statusCode, 200);
  assert.equal((await f.request(f.mobile, 'POST', '/v1/messages', { ...e, expiresAt: e.expiresAt + 1 })).statusCode, 409);
});

test('expired messages are not delivered and revocation clears queued ciphertext durably', async t => {
  const f = await fixture(t), pair = await f.pair();
  const e = f.mobile.seal(f.host, pair, 'fixture', f.clock.value + 1000);
  assert.equal((await f.request(f.mobile, 'POST', '/v1/messages', { ...e, expiresAt: f.clock.value + 600_001 })).statusCode, 400);
  await f.request(f.mobile, 'POST', '/v1/messages', e);
  f.clock.value += 1001;
  assert.equal((await f.request(f.host, 'GET', '/v1/messages')).json().messages.length, 0);
  await f.request(f.mobile, 'POST', '/v1/messages', f.mobile.seal(f.host, pair, 'new', f.clock.value + 60_000));
  assert.equal((await f.request(f.stranger, 'DELETE', `/v1/pairings/${pair}`)).statusCode, 404);
  assert.equal((await f.request(f.host, 'DELETE', `/v1/pairings/${pair}`)).statusCode, 200);
  assert.equal((await f.request(f.host, 'DELETE', `/v1/pairings/${pair}`)).statusCode, 200);
  await f.restart();
  assert.equal((await f.request(f.mobile, 'GET', '/v1/messages')).statusCode, 403);
  assert.equal((await f.request(f.mobile, 'POST', '/v1/messages', f.mobile.seal(f.host, pair, 'blocked', f.clock.value + 60_000))).statusCode, 403);
});

test('HTTP body, schema, origin, query and request-rate limits reject unsafe input', async t => {
  const f = await fixture(t, { requestLimit: 8 });
  assert.equal((await f.app.inject({ url: '/healthz', headers: { origin: 'https://example.invalid' } })).statusCode, 403);
  assert.equal((await f.app.inject({ url: '/healthz?token=not-allowed' })).statusCode, 400);
  assert.equal((await f.app.inject({ method: 'POST', url: '/v1/messages', headers: { 'content-type': 'application/json' }, payload: 'a'.repeat(100_000) })).statusCode, 413);
  assert.equal((await f.app.inject({ method: 'POST', url: '/v1/messages', headers: { 'content-type': 'application/json' }, payload: '{' })).statusCode, 400);
  assert.equal((await f.request(f.host, 'POST', '/v1/pairings', { encryptionKey: f.host.encryptionKey, command: 'ignored?' })).statusCode, 400);
  for (let i = 0; i < 8; i++) await f.app.inject({ url: '/healthz' });
  assert.equal((await f.app.inject({ url: '/healthz', headers: { 'x-forwarded-for': '1.2.3.4' } })).statusCode, 429);
});

test('bounded queues reject overflow without losing already accepted messages', async t => {
  const f = await fixture(t, { requestLimit: 1000 }), pair = await f.pair();
  const e = f.mobile.seal(f.host, pair, 'fixture', f.clock.value + 60_000);
  for (let i = 0; i < 128; i++) {
    const r = await f.request(f.mobile, 'POST', '/v1/messages', { ...e, id: randomUUID() });
    assert.equal(r.statusCode, 200, r.body);
  }
  const overflow = await f.request(f.mobile, 'POST', '/v1/messages', { ...e, id: randomUUID() });
  assert.equal(overflow.statusCode, 429); assert.equal(overflow.json().error, 'queue_full');
  assert.equal((await f.request(f.host, 'GET', '/v1/messages')).json().messages.length, 32);
});

test('same message UUID from two hosts does not let one receipt acknowledge the other host', async t => {
  const f = await fixture(t), first = await f.pair();
  f.settings.allowedHostKeys.add(f.stranger.publicKey);
  const intent = f.stranger.invitation();
  assert.equal((await f.request(f.stranger, 'POST', '/v1/pairings', intent)).statusCode, 200);
  await f.request(f.mobile, 'POST', `/v1/pairings/${intent.id}/claim`, { token: intent.token, encryptionKey: f.mobile.encryptionKey });
  await f.request(f.stranger, 'POST', `/v1/pairings/${intent.id}/approve`, { mobileId: f.mobile.id, repositories: ['repo-one'] });
  const id = randomUUID();
  const e1 = f.host.seal(f.mobile, first, 'first host', f.clock.value + 60_000, id);
  const e2 = f.stranger.seal(f.mobile, intent.id, 'second host', f.clock.value + 60_000, id);
  assert.equal((await f.request(f.host, 'POST', '/v1/messages', e1)).statusCode, 200);
  assert.equal((await f.request(f.stranger, 'POST', '/v1/messages', e2)).statusCode, 200);
  const ack = await f.request(f.mobile, 'POST', '/v1/messages/ack', { receipts: [{ senderId: f.host.id, id }] });
  assert.equal(ack.json().acknowledged, 1);
  const inbox = (await f.request(f.mobile, 'GET', '/v1/messages')).json().messages as Envelope[];
  assert.equal(inbox.length, 1);
  assert.equal(f.mobile.open(f.stranger, inbox[0]!), 'second host');
  await f.request(f.host, 'DELETE', `/v1/pairings/${first}`);
  assert.equal((await f.request(f.mobile, 'GET', '/v1/messages')).json().messages.length, 1);
  assert.equal((await f.request(f.mobile, 'GET', '/v1/devices')).json().devices[0].id, f.stranger.id);
});

async function connect(url: string, client: Client, time: number) {
  const socket = new WebSocket(url + '/v1/socket', { headers: client.headers('GET', '/v1/socket', '', time) });
  const events: { type: string; [key: string]: unknown }[] = [];
  socket.on('message', data => { events.push(JSON.parse(data.toString())); });
  await new Promise<void>((resolve, reject) => { socket.once('open', resolve); socket.once('error', reject); });
  return { socket, events };
}
async function eventually(predicate: () => boolean) {
  const deadline = Date.now() + 3000;
  while (!predicate()) {
    if (Date.now() > deadline) assert.fail('Expected live event did not arrive within 3 seconds');
    await new Promise(resolve => setTimeout(resolve, 10));
  }
}
test('live sockets notify delivery, replace old sessions, report presence and enforce revocation', async t => {
  const f = await fixture(t), pair = await f.pair();
  const address = await f.app.listen({ host: '127.0.0.1', port: 0 });
  const wsURL = address.replace('http:', 'ws:');
  const h = await connect(wsURL, f.host, f.clock.value);
  const m = await connect(wsURL, f.mobile, f.clock.value);
  t.after(() => { h.socket.terminate(); m.socket.terminate(); });
  await eventually(() => h.events.some(e => e.type === 'presence' && e.online === true));
  const replacement = await connect(wsURL, f.mobile, f.clock.value);
  t.after(() => replacement.socket.terminate());
  await eventually(() => m.socket.readyState === WebSocket.CLOSED);
  assert.equal((await f.request(f.host, 'GET', '/v1/devices')).json().devices[0].online, true);
  const e = f.mobile.seal(f.host, pair, 'live fixture', f.clock.value + 60_000);
  h.events.length = 0;
  // This request goes over a real TCP socket, not only Fastify injection.
  const body = JSON.stringify(e);
  const response = await fetch(address + '/v1/messages', { method: 'POST',
    headers: f.mobile.headers('POST', '/v1/messages', body, f.clock.value), body });
  assert.equal(response.status, 200);
  await eventually(() => h.events.some(e => e.type === 'messages.available'));
  const inbox = await fetch(address + '/v1/messages', { headers: f.host.headers('GET', '/v1/messages', '', f.clock.value) });
  const received = await inbox.json() as { messages: Envelope[] };
  assert.equal(f.host.open(f.mobile, received.messages[0]!), 'live fixture');
  await f.request(f.host, 'DELETE', `/v1/pairings/${pair}`);
  await eventually(() => replacement.socket.readyState === WebSocket.CLOSED);
  await assert.rejects(connect(wsURL, f.mobile, f.clock.value));
});

test('WebSocket upgrade rejects missing auth and missed heartbeat marks device offline', async t => {
  const f = await fixture(t, { heartbeatMs: 30 }); await f.pair();
  const url = (await f.app.listen({ host: '127.0.0.1', port: 0 })).replace('http:', 'ws:');
  const unauth = new WebSocket(url + '/v1/socket');
  await new Promise<void>(resolve => { unauth.once('error', error => { assert.match(error.message, /401/); resolve(); }); });
  const socket = new WebSocket(url + '/v1/socket', { autoPong: false,
    headers: f.mobile.headers('GET', '/v1/socket', '', f.clock.value) });
  socket.on('error', () => {});
  t.after(() => socket.terminate());
  await eventually(() => socket.readyState === WebSocket.CLOSED);
  assert.equal((await f.request(f.host, 'GET', '/v1/devices')).json().devices[0].online, false);
});
