import { fail } from './protocol.js';

export class WindowLimit {
  private readonly entries = new Map<string, { end: number; count: number }>();
  constructor(private readonly maxKeys = 2048) {}
  take(key: string, limit: number, now: number): void {
    let entry = this.entries.get(key);
    if (!entry || entry.end <= now) {
      for (const [id, value] of this.entries) if (value.end <= now) this.entries.delete(id);
      if (this.entries.size >= this.maxKeys && !this.entries.has(key)) fail(429, 'rate_limited');
      entry = { end: now + 60_000, count: 0 };
      this.entries.set(key, entry);
    }
    if (++entry.count > limit) fail(429, 'rate_limited');
  }
}
