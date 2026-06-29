"use client";

import { useEffect, useState } from "react";
import { Menu, X, BookOpen, Droplets, Compass } from "lucide-react";
import { WalletSection } from "./WalletSection";
import { NetworkSwitcher } from "./NetworkSwitcher";

function Logo() {
  return (
    <a
      href="/"
      aria-label="Range — home"
      className="tap flex items-center gap-2.5 flex-shrink-0 rounded-lg"
    >
      <span
        className="flex items-center justify-center w-8 h-8 rounded-xl flex-shrink-0"
        style={{
          background: "linear-gradient(180deg, #EB2552 0%, var(--red) 60%, var(--red-dark) 100%)",
          boxShadow: "0 4px 12px rgba(225,29,72,0.28)",
        }}
        aria-hidden="true"
      >
        {/* Range-bar mark: a track with an active segment and current-price knob */}
        <svg width="17" height="17" viewBox="0 0 16 16" fill="none">
          <line x1="2.5" y1="8" x2="13.5" y2="8" stroke="#fff" strokeWidth="1.5" strokeLinecap="round" opacity="0.45" />
          <line x1="5" y1="8" x2="11" y2="8" stroke="#fff" strokeWidth="1.75" strokeLinecap="round" />
          <circle cx="8" cy="8" r="2.5" fill="#fff" />
          <circle cx="8" cy="8" r="1" fill="var(--red)" />
        </svg>
      </span>
      <span className="font-bold text-[17px] tracking-tight" style={{ color: "var(--text)" }}>
        Range
      </span>
    </a>
  );
}

const NAV_LINKS = [
  { label: "Get test tokens", href: "https://faucet.test.mezo.org", icon: Droplets },
  { label: "Explorer", href: "https://explorer.test.mezo.org", icon: Compass },
  { label: "Docs", href: "https://mezo.org/docs", icon: BookOpen },
];

export function Header() {
  const [menuOpen, setMenuOpen] = useState(false);

  // Lock body scroll while drawer is open
  useEffect(() => {
    if (menuOpen) {
      const prev = document.body.style.overflow;
      document.body.style.overflow = "hidden";
      return () => {
        document.body.style.overflow = prev;
      };
    }
  }, [menuOpen]);

  return (
    <header className="glass-header sticky top-0 z-40">
      <div className="max-w-5xl mx-auto px-4 sm:px-5 h-16 flex items-center justify-between gap-3">
        <Logo />

        {/* Desktop cluster */}
        <div className="hidden md:flex items-center gap-2.5">
          <nav className="flex items-center gap-1 mr-1">
            {NAV_LINKS.map((l) => (
              <a
                key={l.label}
                href={l.href}
                target="_blank"
                rel="noreferrer"
                className="tap text-sm font-medium px-3 h-9 flex items-center rounded-xl transition-colors"
                style={{ color: "var(--text-2)" }}
                onMouseEnter={(e) => (e.currentTarget.style.color = "var(--text)")}
                onMouseLeave={(e) => (e.currentTarget.style.color = "var(--text-2)")}
              >
                {l.label}
              </a>
            ))}
          </nav>
          <NetworkSwitcher />
          <WalletSection />
        </div>

        {/* Mobile cluster */}
        <div className="flex md:hidden items-center gap-2">
          <WalletSection />
          <button
            type="button"
            onClick={() => setMenuOpen(true)}
            aria-label="Open menu"
            className="tap btn-ghost flex items-center justify-center w-11 h-11 rounded-2xl cursor-pointer"
          >
            <Menu className="w-5 h-5" style={{ color: "var(--text)" }} />
          </button>
        </div>
      </div>

      {/* Mobile drawer */}
      {menuOpen && (
        <div className="fixed inset-0 z-50 md:hidden">
          {/* Scrim */}
          <div
            className="absolute inset-0"
            style={{ background: "rgba(13,13,18,0.5)", animation: "scrim-in 220ms ease both" }}
            onClick={() => setMenuOpen(false)}
            aria-hidden="true"
          />
          {/* Sheet */}
          <div
            className="absolute right-0 top-0 bottom-0 w-[82%] max-w-[340px] flex flex-col"
            style={{
              background: "var(--surface-2)",
              boxShadow: "var(--shadow-lg)",
              animation: "sheet-in 280ms cubic-bezier(0.16,1,0.3,1) both",
              paddingTop: "env(safe-area-inset-top)",
            }}
            role="dialog"
            aria-modal="true"
            aria-label="Menu"
          >
            <div
              className="flex items-center justify-between h-16 px-5"
              style={{ borderBottom: "1px solid var(--border)" }}
            >
              <span className="font-bold text-base tracking-tight" style={{ color: "var(--text)" }}>
                Menu
              </span>
              <button
                type="button"
                onClick={() => setMenuOpen(false)}
                aria-label="Close menu"
                className="tap btn-ghost flex items-center justify-center w-10 h-10 rounded-xl cursor-pointer"
              >
                <X className="w-5 h-5" style={{ color: "var(--text)" }} />
              </button>
            </div>

            <div className="flex-1 overflow-y-auto px-5 py-5 space-y-5">
              <div className="space-y-2">
                <span className="label">Network</span>
                <NetworkSwitcher block />
              </div>

              <div className="space-y-2">
                <span className="label">Account</span>
                <WalletSection block />
              </div>

              <div className="space-y-1">
                <span className="label">Links</span>
                <nav className="flex flex-col">
                  {NAV_LINKS.map((l) => {
                    const Icon = l.icon;
                    return (
                      <a
                        key={l.label}
                        href={l.href}
                        target="_blank"
                        rel="noreferrer"
                        onClick={() => setMenuOpen(false)}
                        className="tap flex items-center gap-3 px-3 min-h-[48px] rounded-xl text-[15px] font-medium transition-colors"
                        style={{ color: "var(--text)" }}
                        onMouseEnter={(e) => (e.currentTarget.style.background = "var(--surface)")}
                        onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
                      >
                        <Icon className="w-[18px] h-[18px]" style={{ color: "var(--text-3)" }} />
                        {l.label}
                      </a>
                    );
                  })}
                </nav>
              </div>
            </div>
          </div>
        </div>
      )}
    </header>
  );
}
