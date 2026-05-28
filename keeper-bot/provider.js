import { ethers } from "ethers";
import { PRIVATE_KEY, RPC_URL, WS_URL } from "./config.js";
import { networkState } from "./state.js";

function createProvider() {
  return WS_URL
    ? new ethers.WebSocketProvider(WS_URL)
    : new ethers.JsonRpcProvider(RPC_URL);
}

// Exported as live bindings — reassignment in resetProvider() is visible to all importers
export let provider = createProvider();
export let signer   = new ethers.Wallet(PRIVATE_KEY, provider);

export function resetProvider() {
  try { provider.destroy?.(); } catch { /* best-effort */ }
  provider = createProvider();
  signer   = new ethers.Wallet(PRIVATE_KEY, provider);
  networkState.failures = 0;
}
