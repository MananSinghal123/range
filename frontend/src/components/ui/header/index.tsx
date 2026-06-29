"use client";

import { WalletSection } from "./WalletSection";

function Logo() {
  return (
    <a
      href="/"
      aria-label="Range — home"
      className="flex items-center gap-2.5 flex-shrink-0 rounded-md"
    >
      <span
        className="flex items-center justify-center w-7 h-7 rounded-lg flex-shrink-0"
        style={{ background: "var(--red)" }}
        aria-hidden="true"
      >
        {/* Range-bar mark: a track with an active segment and current-price knob */}
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
          <line
            x1="2.5"
            y1="8"
            x2="13.5"
            y2="8"
            stroke="#fff"
            strokeWidth="1.5"
            strokeLinecap="round"
            opacity="0.45"
          />
          <line
            x1="5"
            y1="8"
            x2="11"
            y2="8"
            stroke="#fff"
            strokeWidth="1.75"
            strokeLinecap="round"
          />
          <circle cx="8" cy="8" r="2.5" fill="#fff" />
          <circle cx="8" cy="8" r="1" fill="var(--red)" />
        </svg>
      </span>
      <span
        className="font-semibold text-[15px] tracking-tight"
        style={{ color: "var(--text)" }}
      >
        Range
      </span>
    </a>
  );
}

export function Header() {
  return (
    <header
      className="sticky top-0 z-50 bg-white"
      style={{ borderBottom: "1px solid var(--border)" }}
    >
      <div className="max-w-5xl mx-auto px-5 h-14 flex items-center justify-between gap-3">
        <Logo />
        <WalletSection />
      </div>
    </header>
  );
}
