import { ethers } from "ethers";
import { provider } from "./provider.js";
import { POOL_ABI } from "./config.js";
import { vaultState } from "./state.js";
import { checkAndRebalance } from "./rebalancer.js";
import { logInfo, logErr } from "./logger.js";

export function attachSwapListener(watched) {
  const pool = new ethers.Contract(watched.pool, POOL_ABI, provider);

  pool.on("Swap", async (_sender, _recipient, _amt0, _amt1, sqrtPriceX96, _liq, tick, event) => {
    const vs = vaultState[watched.vault];
    const blockNumber = event?.log?.blockNumber ?? 0;

    // Deduplicate: one check per block — a single block can emit many swaps
    if (blockNumber && blockNumber === vs.lastSwapCheckBlock) return;
    vs.lastSwapCheckBlock = blockNumber;

    logInfo(watched.label, `Swap block=${blockNumber} tick=${tick} sqrtPrice=${sqrtPriceX96}`);
    await checkAndRebalance(watched).catch((err) =>
      logErr(watched.label, err instanceof Error ? err.message : String(err))
    );
  });

  logInfo("events", `listening to Swap on pool=${watched.pool} for ${watched.label}`);
  return pool;
}
