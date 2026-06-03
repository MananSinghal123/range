"use client";

import { useReadContracts, useReadContract, useAccount } from "wagmi";
import { VAULT_ABI, VAULT_LENS_ADDRESS, VAULT_LENS_ABI, ERC20_ABI } from "@/lib/contracts";

export function useVaultState(vaultAddress: `0x${string}`) {
  const results = useReadContracts({
    contracts: [
      { address: vaultAddress, abi: VAULT_ABI, functionName: "symbol" },
      { address: vaultAddress, abi: VAULT_ABI, functionName: "totalAssets" },
      { address: vaultAddress, abi: VAULT_ABI, functionName: "totalSupply" },
      { address: VAULT_LENS_ADDRESS, abi: VAULT_LENS_ABI, functionName: "sharePrice", args: [vaultAddress] },
      { address: vaultAddress, abi: VAULT_ABI, functionName: "paused" },
      { address: vaultAddress, abi: VAULT_ABI, functionName: "performanceFeeBps" },
      { address: vaultAddress, abi: VAULT_ABI, functionName: "tokenId" },
      { address: vaultAddress, abi: VAULT_ABI, functionName: "token0" },
      { address: vaultAddress, abi: VAULT_ABI, functionName: "token1" },
      { address: vaultAddress, abi: VAULT_ABI, functionName: "decimals0" },
      { address: vaultAddress, abi: VAULT_ABI, functionName: "decimals1" },
    ],
    query: { refetchInterval: 10_000 },
  });

  const data = results.data;
  const tokenId = data?.[6]?.result as bigint | undefined;
  const initialized = tokenId !== undefined && tokenId !== BigInt(0);

  return {
    isLoading: results.isLoading,
    vaultSymbol: (data?.[0]?.result as string | undefined) ?? "mREBAL",
    totalAssets: data?.[1]?.result as bigint | undefined,
    totalSupply: data?.[2]?.result as bigint | undefined,
    sharePrice: data?.[3]?.result as bigint | undefined,
    paused: data?.[4]?.result as boolean | undefined,
    performanceFeeBps: data?.[5]?.result as bigint | undefined,
    tokenId,
    initialized,
    token0Address: data?.[7]?.result as `0x${string}` | undefined,
    token1Address: data?.[8]?.result as `0x${string}` | undefined,
    decimals0: data?.[9]?.result as number | undefined,
    decimals1: data?.[10]?.result as number | undefined,
  };
}

export function usePoolState(vaultAddress: `0x${string}`, initialized: boolean) {
  const poolState = useReadContract({
    address: VAULT_LENS_ADDRESS,
    abi: VAULT_LENS_ABI,
    functionName: "getPoolState",
    args: [vaultAddress],
    query: { enabled: initialized, refetchInterval: 5_000 },
  });

  const position = useReadContract({
    address: VAULT_LENS_ADDRESS,
    abi: VAULT_LENS_ABI,
    functionName: "getPosition",
    args: [vaultAddress],
    query: { enabled: initialized, refetchInterval: 10_000 },
  });

  const outOfRange = useReadContract({
    address: VAULT_LENS_ADDRESS,
    abi: VAULT_LENS_ABI,
    functionName: "isOutOfRange",
    args: [vaultAddress],
    query: { enabled: initialized, refetchInterval: 5_000 },
  });

  const poolData = poolState.data as
    | { sqrtPriceX96: bigint; tick: number }
    | undefined;
  const posData = position.data as
    | { token0: string; token1: string; tickSpacing: number; tickLower: number; tickUpper: number; liquidity: bigint }
    | undefined;

  return {
    sqrtPriceX96: poolData?.sqrtPriceX96,
    currentTick: poolData?.tick,
    tickLower: posData?.tickLower,
    tickUpper: posData?.tickUpper,
    liquidity: posData?.liquidity,
    isOutOfRange: outOfRange.data as boolean | undefined,
    isLoading: poolState.isLoading || position.isLoading,
  };
}

export function useVaultMetrics(vaultAddress: `0x${string}`, initialized: boolean) {
  const result = useReadContract({
    address: VAULT_LENS_ADDRESS,
    abi: VAULT_LENS_ABI,
    functionName: "getVaultMetrics",
    args: [vaultAddress],
    query: { enabled: initialized, refetchInterval: 15_000 },
  });

  const data = result.data as
    | { tvl: bigint; tickLower: number; tickUpper: number; rebalanceCount: bigint; totalFees0Earned: bigint; totalFees1Earned: bigint }
    | undefined;

  return {
    tvl: data?.tvl,
    tickLower: data?.tickLower,
    tickUpper: data?.tickUpper,
    rebalanceCount: data?.rebalanceCount,
    fees0Earned: data?.totalFees0Earned,
    fees1Earned: data?.totalFees1Earned,
    isLoading: result.isLoading,
  };
}

export function useTokenInfo(
  token0Address: `0x${string}` | undefined,
  token1Address: `0x${string}` | undefined,
) {
  const results = useReadContracts({
    contracts: [
      { address: token0Address, abi: ERC20_ABI, functionName: "symbol" },
      { address: token1Address, abi: ERC20_ABI, functionName: "symbol" },
    ],
    query: { enabled: !!(token0Address && token1Address) },
  });

  return {
    symbol0: results.data?.[0]?.result as string | undefined,
    symbol1: results.data?.[1]?.result as string | undefined,
  };
}

export function useUserPosition(
  vaultAddress: `0x${string}`,
  token0Address: `0x${string}` | undefined,
  token1Address: `0x${string}` | undefined,
  _decimals0: number | undefined,
  _decimals1: number | undefined,
) {
  const { address } = useAccount();

  const results = useReadContracts({
    contracts: [
      { address: vaultAddress, abi: VAULT_ABI, functionName: "balanceOf", args: address ? [address] : undefined },
      { address: vaultAddress, abi: VAULT_ABI, functionName: "maxRedeem", args: address ? [address] : undefined },
      { address: token0Address, abi: ERC20_ABI, functionName: "balanceOf", args: address ? [address] : undefined },
      { address: token1Address, abi: ERC20_ABI, functionName: "balanceOf", args: address ? [address] : undefined },
      { address: token0Address, abi: ERC20_ABI, functionName: "allowance", args: address ? [address, vaultAddress] : undefined },
      { address: token1Address, abi: ERC20_ABI, functionName: "allowance", args: address ? [address, vaultAddress] : undefined },
    ],
    query: {
      enabled: !!(address && token0Address && token1Address),
      refetchInterval: 5_000,
    },
  });

  return {
    shares: results.data?.[0]?.result as bigint | undefined,
    maxRedeem: results.data?.[1]?.result as bigint | undefined,
    balance0: results.data?.[2]?.result as bigint | undefined,
    balance1: results.data?.[3]?.result as bigint | undefined,
    allowance0: results.data?.[4]?.result as bigint | undefined,
    allowance1: results.data?.[5]?.result as bigint | undefined,
    isLoading: results.isLoading,
  };
}
