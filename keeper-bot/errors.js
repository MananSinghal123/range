import { POLL_INTERVAL_MS } from "./config.js";

export function isNetworkError(err) {
  const msg = (err instanceof Error ? err.message : String(err)).toLowerCase();
  return ["timeout", "network", "temporarily unavailable", "socket hang up",
          "econnreset", "econnrefused", "enotfound", "fetch failed"].some((f) => msg.includes(f));
}

export function isRetryableError(err) {
  if (isNetworkError(err)) return true;
  const msg = (err instanceof Error ? err.message : String(err)).toLowerCase();
  return ["nonce", "underpriced", "replacement fee too low"].some((f) => msg.includes(f));
}

export function jitter(ms) {
  const delta = ms * 0.15;
  return Math.max(Number(POLL_INTERVAL_MS), Math.round(ms + (Math.random() * 2 - 1) * delta));
}
