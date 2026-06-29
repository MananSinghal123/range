"use client";

import { formatTokenAmount } from "@/lib/utils";
import { useReadContract } from "wagmi";
import { VAULT_ABI } from "@/lib/contracts";

interface Props {
  vaultAddress: `0x${string}`;
  shares?: bigint;
  symbol0?: string;
  decimals0?: number;
  isConnected: boolean;
}

export function UserPosition({
  vaultAddress,
  shares,
  symbol0 = "MUSD",
  decimals0 = 18,
  isConnected,
}: Props) {
  const hasShares = shares !== undefined && shares > BigInt(0);

  const { data: assetValue } = useReadContract({
    address: vaultAddress,
    abi: VAULT_ABI,
    functionName: "convertToAssets",
    args: hasShares ? [shares] : undefined,
    query: { enabled: hasShares && !!vaultAddress, refetchInterval: 10_000 },
  });

  if (!isConnected || !hasShares) return null;

  return (
    <div
      className="rounded-[20px] p-5 space-y-3 animate-in"
      style={{
        background:
          "linear-gradient(155deg, var(--red-bg) 0%, #fff 70%)",
        border: "1px solid var(--red-border)",
        boxShadow: "var(--shadow-glow)",
      }}
    >
      <span className="label" style={{ color: "var(--red)" }}>
        Your Deposit
      </span>

      <div className="flex items-baseline justify-between gap-3">
        <div className="min-w-0">
          <p
            className="mono text-[26px] leading-none font-bold truncate"
            style={{ color: "var(--text)" }}
          >
            {assetValue !== undefined
              ? formatTokenAmount(assetValue as bigint, decimals0, 8)
              : "—"}
          </p>
          <p className="text-sm mt-0.5" style={{ color: "var(--text-2)" }}>
            {symbol0} equivalent
          </p>
        </div>
        <div className="text-right">
          <p className="mono text-sm" style={{ color: "var(--text-2)" }}>
            {formatTokenAmount(shares, decimals0, 6)}
          </p>
          <p className="label mt-0.5">Shares</p>
        </div>
      </div>
    </div>
  );
}
