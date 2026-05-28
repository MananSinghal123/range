"use client";

import { useReadContracts, useReadContract, useAccount } from "wagmi";
import { VAULT_ADDRESS, VAULT_ABI, ERC20_ABI } from "@/lib/contracts";

export function useVaultState() {
  const results = useReadContracts({
    contracts: [
      { address: VAULT_ADDRESS, abi: VAULT_ABI, functionName: "totalAssets" },
      { address: VAULT_ADDRESS, abi: VAULT_ABI, functionName: "totalSupply" },
      { address: VAULT_ADDRESS, abi: VAULT_ABI, functionName: "sharePrice" },
      { address: VAULT_ADDRESS, abi: VAULT_ABI, functionName: "paused" },
      {
        address: VAULT_ADDRESS,
        abi: VAULT_ABI,
        functionName: "performanceFeeBps",
      },
      { address: VAULT_ADDRESS, abi: VAULT_ABI, functionName: "tokenId" },
      { address: VAULT_ADDRESS, abi: VAULT_ABI, functionName: "token0" },
      { address: VAULT_ADDRESS, abi: VAULT_ABI, functionName: "token1" },
      { address: VAULT_ADDRESS, abi: VAULT_ABI, functionName: "strategyType" },
      { address: VAULT_ADDRESS, abi: VAULT_ABI, functionName: "decimals0" },
      { address: VAULT_ADDRESS, abi: VAULT_ABI, functionName: "decimals1" },
    ],
    query: { refetchInterval: 10_000 },
  });

  console.log("Vault state results:", results.data);

  const data = results.data;
  const tokenId = data?.[5]?.result as bigint | undefined;
  const initialized = tokenId !== undefined && tokenId !== BigInt(0);

  return {
    isLoading: results.isLoading,
    totalAssets: data?.[0]?.result as bigint | undefined,
    totalSupply: data?.[1]?.result as bigint | undefined,
    sharePrice: data?.[2]?.result as bigint | undefined,
    paused: data?.[3]?.result as boolean | undefined,
    performanceFeeBps: data?.[4]?.result as bigint | undefined,
    tokenId,
    initialized,
    token0Address: data?.[6]?.result as `0x${string}` | undefined,
    token1Address: data?.[7]?.result as `0x${string}` | undefined,
    strategyType: data?.[8]?.result as number | undefined,
    decimals0: data?.[9]?.result as number | undefined,
    decimals1: data?.[10]?.result as number | undefined,
  };
}

export function usePoolState(initialized: boolean) {
  const poolState = useReadContract({
    address: VAULT_ADDRESS,
    abi: VAULT_ABI,
    functionName: "getPoolState",
    query: { enabled: initialized, refetchInterval: 5_000 },
  });

  const position = useReadContract({
    address: VAULT_ADDRESS,
    abi: VAULT_ABI,
    functionName: "getPosition",
    query: { enabled: initialized, refetchInterval: 10_000 },
  });

  const outOfRange = useReadContract({
    address: VAULT_ADDRESS,
    abi: VAULT_ABI,
    functionName: "isOutOfRange",
    query: { enabled: initialized, refetchInterval: 5_000 },
  });

  const poolData = poolState.data as [bigint, number] | undefined;
  const posData = position.data as
    | [string, string, number, number, number, bigint]
    | undefined;

  return {
    sqrtPriceX96: poolData?.[0],
    currentTick: poolData?.[1],
    tickLower: posData?.[3],
    tickUpper: posData?.[4],
    liquidity: posData?.[5],
    isOutOfRange: outOfRange.data as boolean | undefined,
    isLoading: poolState.isLoading || position.isLoading,
  };
}

export function useVaultMetrics(initialized: boolean) {
  const result = useReadContract({
    address: VAULT_ADDRESS,
    abi: VAULT_ABI,
    functionName: "getVaultMetrics",
    query: { enabled: initialized, refetchInterval: 15_000 },
  });

  const data = result.data as
    | [bigint, number, number, bigint, bigint, bigint]
    | undefined;

  return {
    tvl: data?.[0],
    tickLower: data?.[1],
    tickUpper: data?.[2],
    rebalanceCount: data?.[3],
    fees0Earned: data?.[4],
    fees1Earned: data?.[5],
    isLoading: result.isLoading,
  };
}

export function useTokenInfo(
  token0Address: `0x${string}` | undefined,
  token1Address: `0x${string}` | undefined,
) {
  const results = useReadContracts({
    contracts: [
      {
        address: token0Address,
        abi: ERC20_ABI,
        functionName: "symbol",
      },
      {
        address: token1Address,
        abi: ERC20_ABI,
        functionName: "symbol",
      },
    ],
    query: { enabled: !!(token0Address && token1Address) },
  });

  return {
    symbol0: results.data?.[0]?.result as string | undefined,
    symbol1: results.data?.[1]?.result as string | undefined,
  };
}

export function useUserPosition(
  token0Address: `0x${string}` | undefined,
  token1Address: `0x${string}` | undefined,
  _decimals0: number | undefined,
  _decimals1: number | undefined,
) {
  const { address } = useAccount();

  const results = useReadContracts({
    contracts: [
      {
        address: VAULT_ADDRESS,
        abi: VAULT_ABI,
        functionName: "balanceOf",
        args: address ? [address] : undefined,
      },
      {
        address: VAULT_ADDRESS,
        abi: VAULT_ABI,
        functionName: "maxRedeem",
        args: address ? [address] : undefined,
      },
      {
        address: token0Address,
        abi: ERC20_ABI,
        functionName: "balanceOf",
        args: address ? [address] : undefined,
      },
      {
        address: token1Address,
        abi: ERC20_ABI,
        functionName: "balanceOf",
        args: address ? [address] : undefined,
      },
      {
        address: token0Address,
        abi: ERC20_ABI,
        functionName: "allowance",
        args: address ? [address, VAULT_ADDRESS] : undefined,
      },
      {
        address: token1Address,
        abi: ERC20_ABI,
        functionName: "allowance",
        args: address ? [address, VAULT_ADDRESS] : undefined,
      },
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
