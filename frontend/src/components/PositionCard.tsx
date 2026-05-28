"use client";

import { tickToPrice, formatPrice } from "@/lib/utils";

interface PositionCardProps {
  initialized: boolean;
  currentTick?: number;
  tickLower?: number;
  tickUpper?: number;
  isOutOfRange?: boolean;
  decimals0?: number;
  decimals1?: number;
  symbol0?: string;
  symbol1?: string;
}

export function PositionCard({
  initialized,
  currentTick,
  tickLower,
  tickUpper,
  isOutOfRange,
  decimals0 = 18,
  decimals1 = 8,
  symbol0 = "MUSD",
  symbol1 = "BTC",
}: PositionCardProps) {
  if (!initialized) {
    return (
      <div
        className="rounded-xl p-4"
        style={{
          background: "var(--surface)",
          border: "1px solid var(--border)",
        }}
      >
        <p className="text-sm" style={{ color: "var(--text-2)" }}>
          Position not yet opened.
        </p>
      </div>
    );
  }

  const earning = isOutOfRange === false;
  const lowerPrice =
    tickLower !== undefined
      ? formatPrice(tickToPrice(tickLower, decimals0, decimals1))
      : "—";
  const upperPrice =
    tickUpper !== undefined
      ? formatPrice(tickToPrice(tickUpper, decimals0, decimals1))
      : "—";
  const currentPrice =
    currentTick !== undefined
      ? formatPrice(tickToPrice(currentTick, decimals0, decimals1))
      : "—";

  return (
    <div
      className="rounded-xl p-4 space-y-3"
      style={{
        background: "var(--surface)",
        border: "1px solid var(--border)",
      }}
    >
      {/* Status */}
      <div className="flex items-center justify-between">
        <span className="label">Position</span>
        {isOutOfRange !== undefined && (
          <span
            className="flex items-center gap-1.5 text-xs font-medium"
            style={{ color: earning ? "var(--green)" : "#DC2626" }}
          >
            <span
              className="w-1.5 h-1.5 rounded-full"
              style={{ background: earning ? "var(--green)" : "#DC2626" }}
            />
            {earning ? "Earning fees" : "Rebalancing"}
          </span>
        )}
      </div>

      {/* Price range */}
      <div className="grid grid-cols-3 gap-2 text-center">
        <div>
          <p className="label mb-1">Lower</p>
          <p className="mono text-sm" style={{ color: "var(--text)" }}>
            {lowerPrice}
          </p>
        </div>
        <div>
          <p className="label mb-1">Current</p>
          <p
            className="mono text-sm font-medium"
            style={{ color: "var(--text)" }}
          >
            {currentPrice}
          </p>
        </div>
        <div>
          <p className="label mb-1">Upper</p>
          <p className="mono text-sm" style={{ color: "var(--text)" }}>
            {upperPrice}
          </p>
        </div>
      </div>

      <p className="label">
        {symbol1} per {symbol0}
      </p>
    </div>
  );
}
