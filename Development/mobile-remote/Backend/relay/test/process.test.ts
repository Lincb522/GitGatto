import assert from 'node:assert/strict';
import { spawn, type ChildProcess } from 'node:child_process';
import { once } from 'node:events';
import { mkdtempSync, rmSync } from 'node:fs';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { Client } from './client.js';
import type { Envelope } from '../src/protocol.js';

test('standalone entrypoint persists delivery across a killed process and shuts down on SIGTERM', { timeout: 60_000 }, async t => {
  const directory = mkdtempSync(join(tmpdir(), 'gatto-relay-process-'));
  const reservation = createServer();
  reservation.listen(0, '127.0.0.1'); await once(reservation, 'listening');
  const port = (reservation.address() as { port: number }).port;
  await new Promise<void>(resolve => reservation.close(() => resolve()));
  const host = new Client(), mobile = new Client();
  let child: ChildProcess | undefined;
  t.after(async () => {
    if (child && child.exitCode === null && child.signalCode === null) {
      child.kill('SIGKILL'); await once(child, 'exit');
    }
    rmSync(directory, { recursive: true, force: true });
  });
  async function start() {
    child = spawn(process.execPath, ['dist/main.js'], {
      cwd: new URL('..', import.meta.url), stdio: ['ignore', 'pipe', 'pipe'],
      env: { ...process.env, RELAY_PORT: String(port), RELAY_BIND: '127.0.0.1',
        RELAY_DATA_DIR: directory, RELAY_HOST_KEYS: host.publicKey, RELAY_TRUST_PROXY: '' },
    });
    let output = '', diagnostic = '';
    child.stdout!.on('data', data => { output += data.toString(); });
    child.stderr!.on('data', data => { diagnostic = (diagnostic + data.toString()).slice(-1024); });
    const started = Date.now(), deadline = started + 15_000;
    while (!output.includes('relay.started')) {
      assert.equal(child.exitCode, null, `Relay exited before ready: ${diagnostic}`);
      if (Date.now() > deadline) assert.fail(`Relay did not become ready: ${diagnostic}`);
      await new Promise(resolve => setTimeout(resolve, 20));
    }
    t.diagnostic(`Compiled relay startup ${Date.now() - started} ms`);
  }
  async function request(client: Client, method: string, path: string, value?: unknown) {
    const body = value === undefined ? '' : JSON.stringify(value);
    const response = await fetch(`http://127.0.0.1:${port}${path}`, {
      method, headers: client.headers(method, path, body), ...(body ? { body } : {}),
      signal: AbortSignal.timeout(3000),
    });
    assert.equal(response.status, 200);
    return response.json() as Promise<Record<string, unknown>>;
  }
  await start();
  const invitation = host.invitation();
  await request(host, 'POST', '/v1/pairings', invitation);
  await request(mobile, 'POST', `/v1/pairings/${invitation.id}/claim`, { token: invitation.token, encryptionKey: mobile.encryptionKey });
  await request(host, 'POST', `/v1/pairings/${invitation.id}/approve`, { mobileId: mobile.id, repositories: ['repo-one'] });
  const e = mobile.seal(host, invitation.id, 'survives abrupt relay termination');
  await request(mobile, 'POST', '/v1/messages', e);
  child!.kill('SIGKILL'); await once(child!, 'exit');
  await start();
  const inbox = await request(host, 'GET', '/v1/messages');
  assert.equal(host.open(mobile, (inbox.messages as Envelope[])[0]!), 'survives abrupt relay termination');
  await request(host, 'POST', '/v1/messages/ack', { receipts: [{ senderId: mobile.id, id: e.id }] });
  child!.kill('SIGTERM');
  const [code] = await once(child!, 'exit'); assert.equal(code, 0);
  await start();
  assert.deepEqual((await request(host, 'GET', '/v1/messages')).messages, []);
  child!.kill('SIGTERM'); await once(child!, 'exit');
});
