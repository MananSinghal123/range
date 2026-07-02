import { provider, signer } from "./provider.js";

// All vaults share one signer. When two vaults rebalance in the same cycle
// their tx sends race on getTransactionCount(...,"pending") and collide on the
// same nonce. This serializes nonce assignment + submission across vaults while
// leaving reads (estimateGas) and confirmation (tx.wait) fully parallel.

let chain = Promise.resolve(); // serialization mutex (promise chain)
let nextNonce = null;          // locally tracked next nonce; null = refetch

export function resetNonce() {
  nextNonce = null;
}

// Runs `send(nonce)` under the shared lock, handing it a fresh sequential nonce.
// Only nonce assignment + the send itself are serialized — the returned tx
// response can be awaited (confirmed) by the caller outside the lock.
export function withNonce(send) {
  const run = chain.then(async () => {
    const pending = await provider.getTransactionCount(signer.address, "pending");
    const nonce = nextNonce === null ? pending : Math.max(pending, nextNonce);
    try {
      const response = await send(nonce);
      nextNonce = nonce + 1;
      return response;
    } catch (err) {
      // Refetch on the next send to avoid leaving a nonce gap behind.
      nextNonce = null;
      throw err;
    }
  });
  // Keep the mutex chain alive even if this send rejects.
  chain = run.then(() => {}, () => {});
  return run;
}
