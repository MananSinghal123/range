"use client";

import { formatTokenAmount, formatBps } from "@/lib/utils";

interface VaultStatsProps {
  totalAssets?: bigint;
  sharePrice?: bigint;
  performanceFeeBps?: bigint;
  paused?: boolean;
  decimals0?: number;
  symbol0?: string;
  isLoading: boolean;
  apy?: number;
  rebalanceCount?: bigint | number;
  totalFee0?: bigint;
  tickLower?: number;
  tickUpper?: number;
}

function Stat({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-0.5">
      <span className="label">{label}</span>
      <span className="mono font-medium text-base" style={{ color: "var(--text)" }}>
        {value}
      </span>
    </div>
  );
}

function Sep() {
  return (
    <span
      className="hidden sm:block w-px self-stretch my-1"
      style={{ background: "var(--border)" }}
    />
  );
}

function Skeleton() {
  return (
    <span
      className="inline-block h-4 w-16 rounded"
      style={{ background: "var(--surface)", animation: "pulse 1.5s ease-in-out infinite" }}
    />
  );
}

export function VaultStats({
  totalAssets,
  sharePrice,
  performanceFeeBps,
  paused,
  decimals0,
  symbol0,
  isLoading,
  apy,
  rebalanceCount,
  totalFee0,
  tickLower,
  tickUpper,
}: VaultStatsProps) {
  const d0 = decimals0 ?? 8;
  const sym = symbol0 ?? "TOKEN0";

  return (
    <div
      className="flex flex-wrap gap-x-5 gap-y-4 sm:gap-x-7 items-start py-4"
      style={{ borderTop: "1px solid var(--border)", borderBottom: "1px solid var(--border)" }}
    >
      <Stat
        label="TVL"
        value={
          isLoading ? <Skeleton /> :
          totalAssets !== undefined
            ? `${formatTokenAmount(totalAssets, d0, 6)} ${sym}`
            : "—"
        }
      />
      <Sep />
      <Stat
        label="Range"
        value={
          isLoading ? <Skeleton /> :
          tickLower !== undefined && tickUpper !== undefined
            ? `${tickLower} / ${tickUpper}`
            : "—"
        }
      />
      <Sep />
      <Stat
        label="APY"
        value={
          isLoading ? <Skeleton /> :
          apy !== undefined
            ? `${apy.toFixed(2)}%`
            : "—"
        }
      />
      <Sep />
      <Stat
        label="Fees Earned"
        value={
          isLoading ? <Skeleton /> :
          totalFee0 !== undefined
            ? `${formatTokenAmount(totalFee0, d0, 6)} ${sym}`
            : "—"
        }
      />
      <Sep />
      <Stat
        label="Rebalances"
        value={
          isLoading ? <Skeleton /> :
          rebalanceCount !== undefined ? String(rebalanceCount) : "—"
        }
      />
      <Sep />
      <Stat
        label="Perf Fee"
        value={
          isLoading ? <Skeleton /> :
          performanceFeeBps !== undefined ? formatBps(performanceFeeBps) : "—"
        }
      />
      <Sep />
      <Stat
        label="Share Price"
        value={
          isLoading ? <Skeleton /> :
          sharePrice !== undefined
            ? `${formatTokenAmount(sharePrice, d0, 8)} ${sym}`
            : "—"
        }
      />
      <Sep />
      <Stat
        label="Status"
        value={
          isLoading ? <Skeleton /> :
          paused === undefined ? "—" :
          paused ? (
            <span style={{ color: "var(--error)" }}>Paused</span>
          ) : (
            <span className="flex items-center gap-1.5" style={{ color: "var(--green)" }}>
              <span className="w-1.5 h-1.5 rounded-full flex-shrink-0" style={{ background: "var(--green)" }} />
              Active
            </span>
          )
        }
      />
    </div>
  );
}
