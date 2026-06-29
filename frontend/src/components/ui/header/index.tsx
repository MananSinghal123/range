"use client";

import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { useChainId } from "wagmi";
import { Menu, X, BookOpen, Droplets, Compass, ChevronRight } from "lucide-react";
import { WalletSection } from "./WalletSection";
import { NetworkSwitcher } from "./NetworkSwitcher";

function LogoMark({ size = 32 }: { size?: number }) {
  return (
    <span
      className="flex items-center justify-center rounded-xl flex-shrink-0"
      style={{
        width: size,
        height: size,
        background: "linear-gradient(180deg, #EB2552 0%, var(--red) 60%, var(--red-dark) 100%)",
        boxShadow: "0 4px 12px rgba(225,29,72,0.28)",
      }}
      aria-hidden="true"
    >
      <svg width={size * 0.53} height={size * 0.53} viewBox="0 0 16 16" fill="none">
        <line x1="2.5" y1="8" x2="13.5" y2="8" stroke="#fff" strokeWidth="1.5" strokeLinecap="round" opacity="0.45" />
        <line x1="5" y1="8" x2="11" y2="8" stroke="#fff" strokeWidth="1.75" strokeLinecap="round" />
        <circle cx="8" cy="8" r="2.5" fill="#fff" />
        <circle cx="8" cy="8" r="1" fill="var(--red)" />
      </svg>
    </span>
  );
}

function Logo() {
  return (
    <a href="/" aria-label="Range — home" className="tap flex items-center gap-2.5 flex-shrink-0 rounded-lg">
      <LogoMark />
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
  const [mounted, setMounted] = useState(false);

  useEffect(() => setMounted(true), []);

  // Lock body scroll while drawer is open
  useEffect(() => {
    if (!menuOpen) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = prev;
    };
  }, [menuOpen]);

  // Close on Escape
  useEffect(() => {
    if (!menuOpen) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") setMenuOpen(false);
    }
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
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
            aria-expanded={menuOpen}
            className="tap btn-ghost flex items-center justify-center w-11 h-11 rounded-2xl cursor-pointer"
          >
            <Menu className="w-5 h-5" style={{ color: "var(--text)" }} />
          </button>
        </div>
      </div>

      {/* Mobile drawer — portaled to <body> so `fixed` escapes the
          backdrop-filtered header (which would otherwise become its
          containing block and clip it to the header height). */}
      {mounted &&
        menuOpen &&
        createPortal(
          <MobileDrawer onClose={() => setMenuOpen(false)} />,
          document.body,
        )}
    </header>
  );
}

function MobileDrawer({ onClose }: { onClose: () => void }) {
  const chainId = useChainId();
  const isMainnet = chainId === 31612;

  return (
    <div className="fixed inset-0 z-[100] md:hidden">
      {/* Scrim */}
      <button
        type="button"
        aria-label="Close menu"
        onClick={onClose}
        className="absolute inset-0 cursor-default"
        style={{ background: "rgba(13,13,18,0.45)", animation: "scrim-in 220ms ease both" }}
      />

      {/* Sheet */}
      <div
        role="dialog"
        aria-modal="true"
        aria-label="Menu"
        className="absolute right-0 top-0 bottom-0 w-[86%] max-w-[360px] flex flex-col rounded-l-[24px] overflow-hidden"
        style={{
          background: "var(--surface-2)",
          boxShadow: "-24px 0 60px rgba(16,24,40,0.18)",
          animation: "sheet-in 300ms cubic-bezier(0.16,1,0.3,1) both",
          paddingTop: "env(safe-area-inset-top)",
        }}
      >
        {/* Sheet header */}
        <div
          className="flex items-center justify-between h-16 px-4 flex-shrink-0"
          style={{ borderBottom: "1px solid var(--border)" }}
        >
          <Logo />
          <button
            type="button"
            onClick={onClose}
            aria-label="Close menu"
            className="tap btn-ghost flex items-center justify-center w-10 h-10 rounded-xl cursor-pointer"
          >
            <X className="w-5 h-5" style={{ color: "var(--text)" }} />
          </button>
        </div>

        {/* Sheet body */}
        <div className="flex-1 overflow-y-auto px-4 py-5 space-y-6">
          <section className="space-y-2">
            <span className="label">Network</span>
            <NetworkSwitcher block />
          </section>

          <section className="space-y-2">
            <span className="label">Account</span>
            <WalletSection block />
          </section>

          <section className="space-y-2">
            <span className="label">Links</span>
            <div
              className="rounded-2xl overflow-hidden"
              style={{ border: "1px solid var(--border)", background: "#fff" }}
            >
              {NAV_LINKS.map((l, i) => {
                const Icon = l.icon;
                return (
                  <a
                    key={l.label}
                    href={l.href}
                    target="_blank"
                    rel="noreferrer"
                    onClick={onClose}
                    className="tap flex items-center gap-3 px-4 min-h-[54px] text-[15px] font-medium transition-colors active:opacity-70"
                    style={{
                      color: "var(--text)",
                      borderTop: i === 0 ? "none" : "1px solid var(--border-2)",
                    }}
                  >
                    <span
                      className="flex items-center justify-center w-8 h-8 rounded-lg flex-shrink-0"
                      style={{ background: "var(--surface)" }}
                    >
                      <Icon className="w-[18px] h-[18px]" style={{ color: "var(--text-2)" }} />
                    </span>
                    <span className="flex-1">{l.label}</span>
                    <ChevronRight className="w-4 h-4 flex-shrink-0" style={{ color: "var(--text-3)" }} />
                  </a>
                );
              })}
            </div>
          </section>
        </div>

        {/* Sheet footer */}
        <div
          className="flex items-center gap-2 px-5 h-14 flex-shrink-0 text-xs"
          style={{
            borderTop: "1px solid var(--border)",
            color: "var(--text-3)",
            paddingBottom: "env(safe-area-inset-bottom)",
          }}
        >
          <span
            className="w-1.5 h-1.5 rounded-full"
            style={{ background: isMainnet ? "var(--green)" : "var(--amber)" }}
          />
          Connected to Mezo {isMainnet ? "Mainnet" : "Testnet"}
        </div>
      </div>
    </div>
  );
}
