import { formatUnits } from "viem";

export function sqrtPriceX96ToPrice(
  sqrtPriceX96: bigint,
  decimals0: number,
  decimals1: number
): number {
  if (sqrtPriceX96 === BigInt(0)) return 0;
  const sqrtPrice = Number(sqrtPriceX96) / Math.pow(2, 96);
  const rawPrice = sqrtPrice * sqrtPrice;
  return rawPrice * Math.pow(10, decimals0 - decimals1);
}

export function tickToPrice(
  tick: number,
  decimals0: number,
  decimals1: number
): number {
  return Math.pow(1.0001, tick) * Math.pow(10, decimals0 - decimals1);
}

export function formatPrice(price: number, symbol = ""): string {
  if (price === 0) return "0";
  let formatted: string;
  if (price < 0.00001) {
    formatted = price.toExponential(4);
  } else if (price < 1) {
    formatted = price.toFixed(6);
  } else if (price < 10000) {
    formatted = price.toLocaleString("en-US", { maximumFractionDigits: 4 });
  } else {
    formatted = price.toLocaleString("en-US", { maximumFractionDigits: 2 });
  }
  return symbol ? `${formatted} ${symbol}` : formatted;
}

export function formatTokenAmount(
  amount: bigint,
  decimals: number,
  displayDecimals = 6
): string {
  const formatted = formatUnits(amount, decimals);
  const num = parseFloat(formatted);
  if (num === 0) return "0";
  if (num < 0.000001) return "< 0.000001";
  if (num < 1) return num.toFixed(displayDecimals);
  if (num < 1000) return num.toLocaleString("en-US", { maximumFractionDigits: displayDecimals });
  return num.toLocaleString("en-US", { maximumFractionDigits: 4 });
}

export function formatUSD(value: number): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 2,
  }).format(value);
}

export function formatAddress(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

const MEZO_MAINNET_ID = 31612;

export function explorerTxUrl(chainId: number, txHash: string): string {
  const base =
    chainId === MEZO_MAINNET_ID
      ? "https://explorer.mezo.org"
      : "https://explorer.test.mezo.org";
  return `${base}/tx/${txHash}`;
}

export function formatBps(bps: bigint | number): string {
  const n = typeof bps === "bigint" ? Number(bps) : bps;
  return `${(n / 100).toFixed(2)}%`;
}

export function applySlippage(amount: bigint, slippageBps: number): bigint {
  return (amount * BigInt(10000 - slippageBps)) / BigInt(10000);
}

export const STRATEGY_LABELS: Record<number, string> = {
  0: "Tight",
  1: "Medium",
  2: "Wide",
};

export const STRATEGY_DESCRIPTIONS: Record<number, string> = {
  0: "Narrow ±300 tick range — higher fee density, more frequent rebalancing",
  1: "Balanced ±700 tick range — moderate fees, moderate rebalancing",
  2: "Wide ±1200 tick range — lower fee density, infrequent rebalancing",
};

export const STRATEGY_COLORS: Record<number, string> = {
  0: "text-orange-400 bg-orange-400/10 border-orange-400/20",
  1: "text-yellow-400 bg-yellow-400/10 border-yellow-400/20",
  2: "text-blue-400 bg-blue-400/10 border-blue-400/20",
};

export const DEFAULT_SLIPPAGE_BPS = 50; // 0.5%

export function computeAPY(
  totalFee0: bigint | undefined,
  totalAssets: bigint | undefined,
  decimals0: number,
  firstEventTimestamp: number | undefined,
): number | undefined {
  if (!totalFee0 || !totalAssets || totalAssets === BigInt(0)) return undefined;
  if (!firstEventTimestamp) return undefined;
  const elapsedDays = (Date.now() / 1000 - firstEventTimestamp) / 86400;
  if (elapsedDays < 0.01) return undefined;
  const fees = Number(totalFee0) / Math.pow(10, decimals0);
  const tvl  = Number(totalAssets) / Math.pow(10, decimals0);
  if (tvl === 0) return undefined;
  return (fees / tvl) * (365 / elapsedDays) * 100;
}
