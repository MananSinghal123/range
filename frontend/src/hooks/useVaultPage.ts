"use client";

import { useAccount } from "wagmi";
import {
  useVaultState,
  usePoolState,
  useTokenInfo,
  useUserPosition,
  useVaultMetrics,
} from "@/hooks/useVault";
import { useVaultEvents } from "@/hooks/useVaultEvents";
import { computeAPY } from "@/lib/utils";

export function useVaultPage(vaultAddress: `0x${string}`) {
  const { isConnected } = useAccount();

  const vault = useVaultState(vaultAddress);
  const pool = usePoolState(vaultAddress, vault.initialized);
  const metrics = useVaultMetrics(vaultAddress, vault.initialized);
  const tokens = useTokenInfo(vault.token0Address, vault.token1Address);
  const user = useUserPosition(
    vaultAddress,
    vault.token0Address,
    vault.token1Address,
    vault.decimals0,
    vault.decimals1,
  );
  const events = useVaultEvents(vaultAddress);

  const sym0 = tokens.symbol0 ?? "MUSD";
  const sym1 = tokens.symbol1 ?? "BTC";
  const d0 = vault.decimals0 ?? 18;
  const d1 = vault.decimals1 ?? 8;

  const apy = computeAPY(
    metrics.fees0Earned ?? events.totalFee0,
    vault.totalAssets,
    d0,
    events.firstEventTimestamp,
  );

  return {
    isConnected,
    sym0,
    sym1,
    vaultSymbol: vault.vaultSymbol,
    d0,
    d1,
    vault,
    pool,
    metrics,
    user,
    events,
    apy,
    rebalanceCount: metrics.rebalanceCount ?? events.rebalanceCount,
    totalFee0: metrics.fees0Earned ?? events.totalFee0,
    tickLower: metrics.tickLower ?? pool.tickLower,
    tickUpper: metrics.tickUpper ?? pool.tickUpper,
  };
}
