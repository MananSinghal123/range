"use client";

import { STRATEGIES, StrategyKey } from "@/lib/strategies";

interface Props {
  selected: StrategyKey;
  onSelect: (key: StrategyKey) => void;
}

export function StrategySelector({ selected, onSelect }: Props) {
  return (
    <div className="space-y-2">
      <span className="label">Strategy</span>
      <div className="grid grid-cols-3 gap-2.5 sm:gap-3">
        {(Object.keys(STRATEGIES) as StrategyKey[]).map((key) => {
          const s = STRATEGIES[key];
          const isActive = selected === key;
          return (
            <button
              key={key}
              onClick={() => onSelect(key)}
              aria-pressed={isActive}
              className="tap rounded-2xl p-3 sm:p-4 text-left transition-all duration-200"
              style={{
                background: isActive
                  ? "linear-gradient(180deg, var(--red-bg), #fff)"
                  : "var(--surface-2)",
                border: `1.5px solid ${isActive ? "var(--red-border)" : "var(--border)"}`,
                boxShadow: isActive ? "var(--shadow-glow)" : "var(--shadow-xs)",
              }}
            >
              <div className="flex items-center gap-1.5">
                <span
                  className="w-2 h-2 rounded-full flex-shrink-0 transition-colors"
                  style={{ background: isActive ? "var(--red)" : "var(--border)" }}
                />
                <span
                  className="font-semibold text-[13px] sm:text-sm"
                  style={{ color: isActive ? "var(--red)" : "var(--text)" }}
                >
                  {s.label}
                </span>
              </div>
              <div
                className="text-[11px] sm:text-xs mt-1.5 leading-snug line-clamp-2"
                style={{ color: "var(--text-3)" }}
              >
                {s.description}
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
}
