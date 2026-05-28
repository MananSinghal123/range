import { configuredVaults, POLL_INTERVAL_MS, MAX_GAS_GWEI, WS_URL } from "./config.js";
import { signer, resetProvider } from "./provider.js";
import { vaultState, networkState, PROVIDER_RESET_AFTER, initState } from "./state.js";
import { checkAndRebalance, preflight } from "./rebalancer.js";
import { attachSwapListener } from "./events.js";
import { logInfo, logErr } from "./logger.js";

let stopping = false;

async function main() {
  const watched = configuredVaults().filter((v) => v.vault);
  if (watched.length === 0) {
    logErr("boot", "No vault addresses configured.");
    process.exit(1);
  }

  watched.forEach(initState);

  logInfo("boot", `account=${signer.address}`);
  logInfo("boot", `watching ${watched.length} vault(s) | poll=${POLL_INTERVAL_MS}ms | maxGas=${MAX_GAS_GWEI}gwei`);

  await preflight();

  process.on("SIGINT",  () => { if (!stopping) { stopping = true; logInfo("shutdown", "SIGINT received");  } });
  process.on("SIGTERM", () => { if (!stopping) { stopping = true; logInfo("shutdown", "SIGTERM received"); } });

  let poolContracts = WS_URL ? watched.filter((v) => v.pool).map((v) => attachSwapListener(v)) : [];

  let cycle = 0;
  while (!stopping) {
    cycle += 1;

    if (cycle % 5 === 0) {
      const summary = watched
        .map((w) => {
          const s = vaultState[w.vault];
          return `${w.label}=R${s.totalRebalances}/F${s.consecutiveFailures}`;
        })
        .join(" ");
      logInfo("heartbeat", `cycle=${cycle} ${summary}`);
    }

    await Promise.allSettled(watched.map((v) => checkAndRebalance(v)));

    if (networkState.failures >= PROVIDER_RESET_AFTER) {
      logErr("runtime", `${networkState.failures} network failures — reconnecting provider`);
      poolContracts.forEach((c) => c.removeAllListeners("Swap"));
      resetProvider();
      poolContracts = WS_URL ? watched.filter((v) => v.pool).map((v) => attachSwapListener(v)) : [];
    }

    await new Promise((resolve) => setTimeout(resolve, Number(POLL_INTERVAL_MS)));
  }

  poolContracts.forEach((c) => c.removeAllListeners("Swap"));
  logInfo("shutdown", "goodbye");
  process.exit(0);
}

main().catch((err) => {
  logErr("fatal", err instanceof Error ? err.message : String(err));
  process.exit(1);
});
