export const STRATEGIES = {
  tight: {
    label: "Tight",
    description: "Narrow range, higher fees, more rebalances",
    vaultAddress: process.env.NEXT_PUBLIC_VAULT_MUSD_BTC_TIGHT as `0x${string}`,
  },
  medium: {
    label: "Medium",
    description: "Balanced range and rebalance frequency",
    vaultAddress: process.env
      .NEXT_PUBLIC_VAULT_MUSD_BTC_MEDIUM as `0x${string}`,
  },
  wide: {
    label: "Wide",
    description: "Wide range, lower fees, fewer rebalances",
    vaultAddress: process.env.NEXT_PUBLIC_VAULT_MUSD_BTC_WIDE as `0x${string}`,
  },
} as const;

export type StrategyKey = keyof typeof STRATEGIES;

export const DEFAULT_STRATEGY: StrategyKey = "tight";

export function resolveStrategy(param: string | null): StrategyKey {
  if (param === "medium" || param === "wide" || param === "tight") return param;
  return DEFAULT_STRATEGY;
}
