import "dotenv/config";
import { ethers } from "ethers";
import { readFileSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { logErr } from "./logger.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

export const {PRIVATE_KEY,RPC_URL,WS_URL,POLL_INTERVAL_MS = "30000", MAX_GAS_GWEI = "50", LENS_ADDRESS} = process.env;

export const MAX_GAS_PRICE = ethers.parseUnits(MAX_GAS_GWEI, "gwei");

if (!PRIVATE_KEY || !RPC_URL) {
  logErr("boot", "Missing required env vars: PRIVATE_KEY and RPC_URL must be set.");
  process.exit(1);
}

const VALID_STRATEGIES = { TIGHT: 0, MEDIUM: 1, WIDE: 2 };

function parseStrategy(raw, label) {
  if (raw === undefined || raw === "") {
    logErr("boot", `${label}: STRATEGY must be explicitly set (0=TIGHT, 1=MEDIUM, 2=WIDE)`);
    process.exit(1);
  }
  const n = Number(raw);
  if (!Object.values(VALID_STRATEGIES).includes(n)) {
    logErr("boot", `${label}: invalid strategy "${raw}" — must be 0 (TIGHT), 1 (MEDIUM), or 2 (WIDE)`);
    process.exit(1);
  }
  return n;
}

export function configuredVaults() {
  const vaultAddrs   = (process.env.VAULT_ADDRS ?? "").split(",").map((v) => v.trim()).filter(Boolean);
  const poolAddrs    = (process.env.POOL_ADDRS  ?? "").split(",").map((v) => v.trim()).filter(Boolean);
  const lensAddrs    = (process.env.LENS_ADDRS  ?? "").split(",").map((v) => v.trim()).filter(Boolean);
  const strategyRaws = (process.env.STRATEGIES  ?? process.env.STRATEGY ?? "")
    .split(",").map((v) => v.trim());

  if (vaultAddrs.length > 0) {
    return vaultAddrs.map((vault, i) => {
      const label = `vault-${i + 1}`;
      return {
        label,
        vault,
        pool:     poolAddrs[i] ?? "",
        lens:     lensAddrs[i] ?? LENS_ADDRESS ?? "",
        strategy: parseStrategy(strategyRaws[i] ?? strategyRaws[0], label),
      };
    });
  }

  return [{
    label:    "vault-1",
    vault:    process.env.VAULT_ADDRESS ?? "",
    pool:     process.env.POOL_ADDRESS  ?? "",
    lens:     LENS_ADDRESS ?? "",
    strategy: parseStrategy(process.env.STRATEGY, "vault-1"),
  }];
}

export const RebalancerVaultABI = JSON.parse(
  readFileSync(join(__dirname, "abi/RebalancerVault.json"), "utf8")
);

export const POOL_ABI = [
  "event Swap(address indexed sender, address indexed recipient, int256 amount0, int256 amount1, uint160 sqrtPriceX96, uint128 liquidity, int24 tick)",
];
