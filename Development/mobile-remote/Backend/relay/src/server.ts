import Fastify, { type FastifyRequest } from 'fastify';
import websocket from '@fastify/websocket';
import type { WebSocket } from 'ws';
import { z } from 'zod';
import { RelayStore } from './store.js';
import { WindowLimit } from './limits.js';
import { ackSchema, approvePairSchema, claimPairSchema, createPairSchema, deviceId,
  envelopeSchema, fail, idSchema, keySchema, RelayError, signatureInput, verifySignature } from './protocol.js';

declare module 'fastify' {
  interface FastifyRequest { signedBody: Buffer | null; device: string; signingKey: string }
}
export interface RelayOptions {
  databasePath: string;
  allowedHostKeys: ReadonlySet<string>;
  now?: () => number;
  heartbeatMs?: number;
  requestLimit?: number;
  trustedProxies?: string[];
}
export async function buildRelay(options: RelayOptions) {
  const now = options.now ?? Date.now;
  const store = new RelayStore(options.databasePath);
  const limits = new WindowLimit();
  const sockets = new Map<string, { socket: WebSocket; alive: boolean }>();
  const app = Fastify({ logger: false, bodyLimit: 96 * 1024, requestTimeout: 10_000,
    connectionTimeout: 15_000, keepAliveTimeout: 5_000, trustProxy: options.trustedProxies ?? false });
  app.server.maxConnections = 512;
  let storageHealthy = true;
  app.decorateRequest('signedBody', null);
  app.decorateRequest('device', '');
  app.decorateRequest('signingKey', '');
  app.removeAllContentTypeParsers();
  app.addContentTypeParser('application/json', { parseAs: 'buffer' }, (request, body, done) => {
    request.signedBody = body as Buffer;
    try { done(null, JSON.parse((body as Buffer).toString('utf8'))); }
    catch { done(new RelayError(400, 'invalid_json')); }
  });
  app.setErrorHandler((error: unknown, _request, reply) => {
    if (error instanceof RelayError) {
      if (error.status === 429) reply.header('Retry-After', '60');
      return reply.code(error.status).send({ error: error.code });
    }
    if (error instanceof z.ZodError) return reply.code(400).send({ error: 'invalid_request' });
    const status = (error as { statusCode?: number }).statusCode;
    if (status && status >= 400 && status < 500) return reply.code(status).send({ error: 'invalid_request' });
    // Do not serialize exception messages containing SQL, request bodies or keys.
    return reply.code(503).send({ error: 'service_unavailable' });
  });
  app.addHook('onRequest', async (request, reply) => {
    reply.header('Cache-Control', 'no-store');
    reply.header('X-Content-Type-Options', 'nosniff');
    if (request.headers.origin) fail(403, 'native_client_required');
    if (request.url.includes('?')) fail(400, 'query_parameters_not_supported');
    limits.take('global', 3000, now());
    limits.take('ip:' + request.ip, options.requestLimit ?? 180, now());
  });
  const authenticate = async (request: FastifyRequest) => {
    const publicKey = request.headers['x-gatto-key'], time = request.headers['x-gatto-time'];
    const nonce = request.headers['x-gatto-nonce'], signature = request.headers['x-gatto-signature'];
    if (typeof publicKey !== 'string' || !keySchema.safeParse(publicKey).success
      || typeof time !== 'string' || !/^\d{13}$/.test(time)
      || typeof nonce !== 'string' || !/^[a-f0-9]{32}$/.test(nonce)
      || typeof signature !== 'string' || !/^[a-f0-9]{128}$/.test(signature)) fail(401, 'invalid_authentication');
    const timestamp = Number(time), current = now();
    if (Math.abs(current - timestamp) > 60_000) fail(401, 'request_expired');
    const bytes = signatureInput(request.method, request.url, publicKey, time, nonce, request.signedBody ?? Buffer.alloc(0));
    if (!verifySignature(publicKey, signature, bytes)) fail(401, 'invalid_authentication');
    const id = deviceId(publicKey);
    limits.take('device:' + id, 240, current);
    store.consumeNonce(id, nonce, timestamp + 60_001, current);
    request.device = id; request.signingKey = publicKey;
  };
  const active = async (request: FastifyRequest) => { await authenticate(request); store.requireActive(request.device); };
  const notify = (id: string | null, event: object) => {
    if (!id) return;
    const entry = sockets.get(id);
    if (!entry || entry.socket.readyState !== 1) return;
    if (entry.socket.bufferedAmount > 128 * 1024) { entry.socket.terminate(); return; }
    entry.socket.send(JSON.stringify(event));
  };
  const presence = (id: string, online: boolean) => {
    for (const p of store.activePairs(id)) notify(p.hostId === id ? p.mobileId : p.hostId,
      { type: 'presence', deviceId: id, online, at: now() });
  };
  await app.register(websocket, { options: { maxPayload: 1024, perMessageDeflate: false },
    preClose(done) { for (const entry of sockets.values()) entry.socket.terminate(); sockets.clear(); done(); },
  });
  app.get('/healthz', async () => {
    if (!storageHealthy) fail(503, 'storage_unavailable');
    return { status: 'ok', protocol: 1 };
  });
  app.get('/v1/pairings', { preHandler: authenticate }, async request => ({ pairings: store.listPairs(request.device) }));
  app.post('/v1/pairings', { preHandler: authenticate }, async request => {
    if (!options.allowedHostKeys.has(request.signingKey)) fail(403, 'host_not_enrolled');
    const body = createPairSchema.parse(request.body);
    return store.createPair(body.id, body.token, request.signingKey, body.encryptionKey, now());
  });
  app.post('/v1/pairings/:id/claim', { preHandler: authenticate }, async request => {
    const { id } = z.object({ id: idSchema }).parse(request.params);
    const body = claimPairSchema.parse(request.body);
    const result = store.claimPair(id, body.token, request.signingKey, body.encryptionKey, now());
    notify(result.host?.id ?? null, { type: 'pairing.changed', pairingId: id });
    return result;
  });
  app.get('/v1/pairings/:id', { preHandler: authenticate }, async request => {
    const { id } = z.object({ id: idSchema }).parse(request.params);
    return store.viewPair(id, request.device);
  });
  app.post('/v1/pairings/:id/approve', { preHandler: authenticate }, async request => {
    const { id } = z.object({ id: idSchema }).parse(request.params);
    const body = approvePairSchema.parse(request.body);
    return store.approvePair(id, request.device, body.mobileId, body.repositories, now());
  });
  app.delete('/v1/pairings/:id', { preHandler: authenticate }, async request => {
    const { id } = z.object({ id: idSchema }).parse(request.params);
    const p = store.revokePair(id, request.device, now());
    for (const device of [p.hostId, p.mobileId]) {
      notify(device, { type: 'pairing.revoked', pairingId: id });
      if (device && !store.activePairs(device).length) sockets.get(device)?.socket.close(4003, 'Pairing revoked');
    }
    return { state: 'revoked' };
  });
  app.get('/v1/devices', { preHandler: active }, async request => ({
    devices: [...new Set(store.activePairs(request.device).map(p => p.hostId === request.device ? p.mobileId! : p.hostId))]
      .map(id => ({ id, online: sockets.get(id)?.socket.readyState === 1, lastSeen: store.device(id)?.lastSeen ?? 0 })),
    serverTime: now(),
  }));
  app.post('/v1/messages', { preHandler: active }, async request => {
    const body = envelopeSchema.parse(request.body);
    const result = store.send(body, request.device, now());
    if (result.state === 'queued') notify(body.recipientId, { type: 'messages.available' });
    return result;
  });
  app.get('/v1/messages', { preHandler: active }, async request => ({ messages: store.inbox(request.device, now()) }));
  app.get('/v1/messages/:id/receipt', { preHandler: active }, async request => {
    const { id } = z.object({ id: idSchema }).parse(request.params);
    return store.receipt(request.device, id, now());
  });
  app.post('/v1/messages/ack', { preHandler: active }, async request => {
    const body = ackSchema.parse(request.body);
    return { acknowledged: store.ack(request.device, body.receipts, now()) };
  });
  app.get('/v1/socket', { websocket: true, preValidation: async request => {
    await authenticate(request);
    if (!(options.allowedHostKeys.has(request.signingKey) && store.device(request.device))) store.requireActive(request.device);
  } }, (socket, request) => {
    const id = request.device;
    const previous = sockets.get(id);
    const entry = { socket, alive: true };
    sockets.set(id, entry);
    previous?.socket.close(4001, 'Connection replaced');
    store.seen(id, now());
    socket.on('error', () => socket.terminate());
    socket.on('message', () => socket.close(1008, 'Use signed HTTP requests'));
    const limitFrames = () => {
      try { limits.take('frames:' + id, 120, now()); return true; }
      catch { socket.close(1008, 'Control frame limit'); return false; }
    };
    socket.on('ping', limitFrames);
    socket.on('pong', () => {
      if (!limitFrames() || sockets.get(id) !== entry) return;
      entry.alive = true;
      try { store.seen(id, now()); } catch { socket.close(1011, 'Storage unavailable'); }
    });
    socket.on('close', () => {
      if (sockets.get(id) !== entry) return;
      sockets.delete(id);
      presence(id, false);
    });
    notify(id, { type: 'ready', protocol: 1, serverTime: now() });
    presence(id, true);
    notify(id, { type: 'messages.available' });
  });
  store.cleanup(now());
  const heartbeat = setInterval(() => {
    for (const entry of sockets.values()) {
      if (!entry.alive) { entry.socket.terminate(); continue; }
      entry.alive = false; entry.socket.ping();
    }
  }, options.heartbeatMs ?? 15_000).unref();
  const cleanup = setInterval(() => {
    try {
      store.cleanup(now());
      if (!storageHealthy) process.stderr.write('{"event":"relay.storage_recovered"}\n');
      storageHealthy = true;
    } catch {
      if (storageHealthy) process.stderr.write('{"event":"relay.storage_unavailable"}\n');
      storageHealthy = false;
    }
  }, 30_000).unref();
  app.addHook('onClose', async () => { clearInterval(heartbeat); clearInterval(cleanup); store.close(); });
  return app;
}
