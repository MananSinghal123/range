"use client";

import { STRATEGIES, StrategyKey } from "@/lib/strategies";

interface Props {
  selected: StrategyKey;
  onSelect: (key: StrategyKey) => void;
}

export function StrategySelector({ selected, onSelect }: Props) {
  return (
    <div className="grid grid-cols-3 gap-3">
      {(Object.keys(STRATEGIES) as StrategyKey[]).map((key) => {
        const s = STRATEGIES[key];
        const isActive = selected === key;
        return (
          <button
            key={key}
            onClick={() => onSelect(key)}
            className="rounded-lg p-4 text-left transition-colors"
            style={{
              background: isActive ? "var(--red-bg)" : "var(--surface)",
              border: `1px solid ${isActive ? "var(--red-border)" : "var(--border)"}`,
              color: isActive ? "var(--red)" : "var(--text-2)",
            }}
          >
            <div
              className="font-semibold text-sm"
              style={{ color: isActive ? "var(--red)" : "var(--text)" }}
            >
              {s.label}
            </div>
            <div className="text-xs mt-1" style={{ color: "var(--text-3)" }}>
              {s.description}
            </div>
          </button>
        );
      })}
    </div>
  );
}
