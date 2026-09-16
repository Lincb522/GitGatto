import { mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { isIP } from 'node:net';
import { z } from 'zod';
import { keySchema } from './protocol.js';
import { buildRelay } from './server.js';

process.umask(0o077);
const host = process.env.RELAY_BIND ?? '127.0.0.1';
const port = z.coerce.number().int().min(1).max(65535).parse(process.env.RELAY_PORT ?? '8787');
// Enrollment contains public Ed25519 keys only. No GitHub/Agent credentials belong here.
const hostKeys = z.array(keySchema).min(1).max(1000).parse((process.env.RELAY_HOST_KEYS ?? '').split(',').filter(Boolean));
const directory = resolve(process.env.RELAY_DATA_DIR ?? './data');
mkdirSync(directory, { recursive: true, mode: 0o700 });
const trustedProxies = z.array(z.string().refine(ip => isIP(ip) !== 0)).max(10)
  .parse((process.env.RELAY_TRUST_PROXY ?? '').split(',').filter(Boolean));
const app = await buildRelay({ databasePath: resolve(directory, 'relay.sqlite'),
  allowedHostKeys: new Set(hostKeys), trustedProxies });
let stopping = false;
async function stop() {
  if (stopping) return;
  stopping = true;
  await app.close();
}
process.once('SIGINT', () => { void stop(); });
process.once('SIGTERM', () => { void stop(); });
try {
  await app.listen({ host, port });
  process.stdout.write(JSON.stringify({ event: 'relay.started', host, port, protocol: 1 }) + '\n');
} catch {
  process.stderr.write('Relay startup failed. Check bind address, port and data-directory access.\n');
  await stop(); process.exitCode = 1;
}
