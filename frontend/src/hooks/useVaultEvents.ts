"use client";

import { useEffect, useState, useCallback } from "react";
import { usePublicClient, useChainId } from "wagmi";
import { VAULT_ADDRESS, VAULT_ABI } from "@/lib/contracts";

export interface RebalanceEvent {
  blockNumber: bigint;
  txHash: `0x${string}`;
  timestamp: number;
  tickLower: number;
  tickUpper: number;
  liquidity: bigint;
}

export interface VaultEventsData {
  rebalances: RebalanceEvent[];
  rebalanceCount: number;
  totalFee0: bigint;
  totalFee1: bigint;
  firstEventTimestamp: number | undefined;
  isLoading: boolean;
}

const REBALANCED_ABI = VAULT_ABI.find((x) => x.name === "Rebalanced" && x.type === "event")!;
const FEES_ABI = VAULT_ABI.find((x) => x.name === "FeesCollected" && x.type === "event")!;

export function useVaultEvents(): VaultEventsData {
  const client = usePublicClient();
  const chainId = useChainId();

  const [data, setData] = useState<VaultEventsData>({
    rebalances: [],
    rebalanceCount: 0,
    totalFee0: BigInt(0),
    totalFee1: BigInt(0),
    firstEventTimestamp: undefined,
    isLoading: true,
  });

  const fetchEvents = useCallback(async () => {
    if (!client) return;
    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const [rbLogs, feeLogs]: [any[], any[]] = await Promise.all([
        client.getLogs({
          address: VAULT_ADDRESS,
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          event: REBALANCED_ABI as any,
          fromBlock: "earliest",
        }),
        client.getLogs({
          address: VAULT_ADDRESS,
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          event: FEES_ABI as any,
          fromBlock: "earliest",
        }),
      ]);

      // Collect unique block numbers, then fetch timestamps in parallel
      const blockNums = new Set<bigint>();
      for (const log of [...rbLogs, ...feeLogs]) {
        if (log.blockNumber != null) blockNums.add(log.blockNumber);
      }
      const tsMap = new Map<bigint, number>();
      await Promise.all(
        Array.from(blockNums).map(async (bn) => {
          try {
            const block = await client.getBlock({ blockNumber: bn });
            tsMap.set(bn, Number(block.timestamp));
          } catch { /* ignore */ }
        })
      );

      const ts = (bn: bigint | null) => (bn != null ? (tsMap.get(bn) ?? 0) : 0);

      const rebalances: RebalanceEvent[] = rbLogs.map((log) => {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const args = log.args as any;
        return {
          blockNumber: log.blockNumber ?? BigInt(0),
          txHash: (log.transactionHash ?? "0x0") as `0x${string}`,
          timestamp: ts(log.blockNumber),
          tickLower: args.newTickLower as number,
          tickUpper: args.newTickUpper as number,
          liquidity: (args.newLiquidity ?? BigInt(0)) as bigint,
        };
      }).reverse(); // newest first

      const totalFee0 = feeLogs.reduce((acc, log) => {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        return acc + (((log.args as any).fee0 as bigint) ?? BigInt(0));
      }, BigInt(0));

      const totalFee1 = feeLogs.reduce((acc, log) => {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        return acc + (((log.args as any).fee1 as bigint) ?? BigInt(0));
      }, BigInt(0));

      const allTs = [
        ...rbLogs.map((l) => ts(l.blockNumber)),
        ...feeLogs.map((l) => ts(l.blockNumber)),
      ].filter(Boolean);

      setData({
        rebalances,
        rebalanceCount: rbLogs.length,
        totalFee0,
        totalFee1,
        firstEventTimestamp: allTs.length > 0 ? Math.min(...allTs) : undefined,
        isLoading: false,
      });
    } catch (e) {
      console.error("useVaultEvents:", e);
      setData((prev) => ({ ...prev, isLoading: false }));
    }
  }, [client, chainId]);

  useEffect(() => {
    fetchEvents();
    const id = setInterval(fetchEvents, 30_000);
    return () => clearInterval(id);
  }, [fetchEvents]);

  return data;
}
