"use client";

import { WalletSection } from "./WalletSection";

export function Header() {
  return (
    <header
      className="sticky top-0 z-50 bg-white"
      style={{ borderBottom: "1px solid var(--border)" }}
    >
      <div className="max-w-5xl mx-auto px-5 h-12 flex items-center justify-between gap-3">
        <div className="flex items-center gap-2 flex-shrink-0">
          <span
            className="w-2 h-2 rounded-full flex-shrink-0"
            style={{ background: "var(--red)" }}
          />
          <span
            className="font-semibold text-sm tracking-tight"
            style={{ color: "var(--text)" }}
          >
            Mezo Rebalancer
          </span>
        </div>
        <WalletSection />
      </div>
    </header>
  );
}
