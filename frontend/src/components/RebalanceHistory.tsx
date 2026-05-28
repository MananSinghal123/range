"use client";

import { useChainId } from "wagmi";
import { tickToPrice, formatPrice } from "@/lib/utils";
import type { RebalanceEvent } from "@/hooks/useVaultEvents";

interface Props {
  rebalances: RebalanceEvent[];
  isLoading: boolean;
  decimals0?: number;
  decimals1?: number;
  symbol0?: string;
  symbol1?: string;
}

function relativeTime(ts: number): string {
  const diffSecs = Math.floor(Date.now() / 1000) - ts;
  if (diffSecs < 60) return "just now";
  if (diffSecs < 3600) return `${Math.floor(diffSecs / 60)}m ago`;
  if (diffSecs < 86400) return `${Math.floor(diffSecs / 3600)}h ago`;
  if (diffSecs < 2592000) return `${Math.floor(diffSecs / 86400)}d ago`;
  return new Date(ts * 1000).toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

function explorerUrl(chainId: number, txHash: string): string {
  const base = chainId === 31612
    ? "https://explorer.mezo.org"
    : "https://explorer.test.mezo.org";
  return `${base}/tx/${txHash}`;
}

function formatAddr(hash: string): string {
  return `${hash.slice(0, 8)}…${hash.slice(-6)}`;
}

export function RebalanceHistory({
  rebalances,
  isLoading,
  decimals0 = 8,
  decimals1 = 18,
  symbol0 = "TOKEN0",
  symbol1 = "TOKEN1",
}: Props) {
  const chainId = useChainId();

  return (
    <div
      className="rounded-xl overflow-hidden"
      style={{ border: "1px solid var(--border)", background: "#fff" }}
    >
      <div
        className="px-4 py-3"
        style={{ borderBottom: "1px solid var(--border)", background: "var(--surface)" }}
      >
        <span className="label">Rebalance History</span>
      </div>

      {isLoading ? (
        <div className="p-4 space-y-3">
          {[...Array(3)].map((_, i) => (
            <div key={i} className="flex justify-between items-center">
              <div
                className="h-3 rounded w-32"
                style={{ background: "var(--surface)", animation: "pulse 1.5s ease-in-out infinite" }}
              />
              <div
                className="h-3 rounded w-16"
                style={{ background: "var(--surface)", animation: "pulse 1.5s ease-in-out infinite" }}
              />
            </div>
          ))}
        </div>
      ) : rebalances.length === 0 ? (
        <div className="p-4 text-center">
          <p className="text-sm" style={{ color: "var(--text-3)" }}>No rebalances yet</p>
        </div>
      ) : (
        <div className="divide-y" style={{ borderColor: "var(--border)" }}>
          {rebalances.slice(0, 10).map((ev, i) => {
            const lowerPrice = tickToPrice(ev.tickLower, decimals0, decimals1);
            const upperPrice = tickToPrice(ev.tickUpper, decimals0, decimals1);
            return (
              <div key={i} className="px-4 py-3 flex items-center justify-between gap-3">
                <div className="min-w-0">
                  <p className="mono text-xs" style={{ color: "var(--text)" }}>
                    {formatPrice(lowerPrice)}
                    <span style={{ color: "var(--text-3)" }}> → </span>
                    {formatPrice(upperPrice)}
                  </p>
                  <p className="label mt-0.5" style={{ color: "var(--text-3)" }}>
                    {symbol1}/{symbol0}
                  </p>
                </div>

                <div className="text-right flex-shrink-0">
                  <a
                    href={explorerUrl(chainId, ev.txHash)}
                    target="_blank"
                    rel="noreferrer"
                    className="mono text-xs transition-colors"
                    style={{ color: "var(--red)" }}
                    onMouseEnter={(e) => (e.currentTarget.style.color = "var(--red-dark)")}
                    onMouseLeave={(e) => (e.currentTarget.style.color = "var(--red)")}
                  >
                    {formatAddr(ev.txHash)}
                  </a>
                  <p className="label mt-0.5" style={{ color: "var(--text-3)" }}>
                    {ev.timestamp > 0 ? relativeTime(ev.timestamp) : "—"}
                  </p>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
