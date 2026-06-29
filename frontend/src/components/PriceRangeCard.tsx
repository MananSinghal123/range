"use client";

import { tickToPrice, formatPrice } from "@/lib/utils";

interface PriceRangeCardProps {
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

function RangeBar({
  tickLower,
  tickUpper,
  currentTick,
  isOutOfRange,
  decimals0,
  decimals1,
}: {
  tickLower: number;
  tickUpper: number;
  currentTick: number;
  isOutOfRange: boolean;
  decimals0: number;
  decimals1: number;
}) {
  const span = tickUpper - tickLower;
  const margin = Math.max(span * 0.35, 1);
  const viewMin = tickLower - margin;
  const viewSpan = (tickUpper + margin) - viewMin;
  const pct = (t: number) => ((t - viewMin) / viewSpan) * 100;

  const rangeLeftPct = pct(tickLower);
  const rangeRightPct = 100 - pct(tickUpper);
  const currentPct = Math.max(0, Math.min(100, pct(currentTick)));

  const inRange = !isOutOfRange;
  const accent = inRange ? "var(--green)" : "var(--error)";
  const fill = inRange ? "rgba(22,163,74,0.12)" : "rgba(220,38,38,0.12)";

  return (
    <div className="space-y-2">
      {/* Visual bar */}
      <div
        className="relative h-6 rounded-lg overflow-hidden"
        style={{ background: "var(--surface)", border: "1px solid var(--border)" }}
      >
        {/* Active range */}
        <div
          className="absolute inset-y-0"
          style={{
            left: `${rangeLeftPct}%`,
            right: `${rangeRightPct}%`,
            background: fill,
            borderLeft: `2px solid ${accent}`,
            borderRight: `2px solid ${accent}`,
          }}
        />
        {/* Current price line */}
        <div
          className="absolute top-0 bottom-0"
          style={{
            left: `${currentPct}%`,
            width: 2,
            transform: "translateX(-50%)",
            background: "var(--text)",
            zIndex: 2,
          }}
        />
        {/* Current price knob */}
        <div
          className="absolute w-3 h-3 rounded-full border-2"
          style={{
            left: `${currentPct}%`,
            top: "50%",
            transform: "translate(-50%, -50%)",
            background: "#fff",
            borderColor: "var(--text)",
            zIndex: 3,
          }}
        />
      </div>

      {/* Price labels below bar */}
      <div className="flex justify-between items-baseline">
        <span className="label">{formatPrice(tickToPrice(tickLower, decimals0, decimals1))}</span>
        <span className="mono text-xs font-semibold" style={{ color: "var(--text)" }}>
          {formatPrice(tickToPrice(currentTick, decimals0, decimals1))}
        </span>
        <span className="label">{formatPrice(tickToPrice(tickUpper, decimals0, decimals1))}</span>
      </div>
    </div>
  );
}

export function PriceRangeCard({
  initialized,
  currentTick,
  tickLower,
  tickUpper,
  isOutOfRange,
  decimals0 = 8,
  decimals1 = 18,
  symbol0 = "TOKEN0",
  symbol1 = "TOKEN1",
}: PriceRangeCardProps) {
  if (!initialized) {
    return (
      <div
        className="rounded-xl p-4"
        style={{ background: "var(--surface)", border: "1px solid var(--border)" }}
      >
        <p className="text-sm" style={{ color: "var(--text-2)" }}>
          Position not yet opened.
        </p>
      </div>
    );
  }

  const earning = isOutOfRange === false;

  return (
    <div
      className="rounded-xl p-4 space-y-3"
      style={{ background: "var(--surface)", border: "1px solid var(--border)" }}
    >
      <div className="flex items-center justify-between">
        <span className="label">Price Range</span>
        {isOutOfRange !== undefined && (
          <span
            className="flex items-center gap-1.5 text-xs font-medium"
            style={{ color: earning ? "var(--green)" : "var(--error)" }}
          >
            <span
              className="w-1.5 h-1.5 rounded-full"
              style={{ background: earning ? "var(--green)" : "var(--error)" }}
            />
            {earning ? "Earning fees" : "Out of range"}
          </span>
        )}
      </div>

      {tickLower !== undefined && tickUpper !== undefined && currentTick !== undefined ? (
        <RangeBar
          tickLower={tickLower}
          tickUpper={tickUpper}
          currentTick={currentTick}
          isOutOfRange={isOutOfRange ?? false}
          decimals0={decimals0}
          decimals1={decimals1}
        />
      ) : (
        <div
          className="h-6 rounded-lg"
          style={{
            background: "var(--surface)",
            border: "1px solid var(--border)",
            animation: "pulse 1.5s ease-in-out infinite",
          }}
        />
      )}

      <p className="label">{symbol1} per {symbol0}</p>
    </div>
  );
}
