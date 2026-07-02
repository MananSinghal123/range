"use client";

import { useEffect, useRef, useState } from "react";
import { useChainId, useSwitchChain } from "wagmi";
import { Check, ChevronDown, Loader2 } from "lucide-react";
import { mezoMainnet, mezoTestnet } from "@/config/wagmi";

const NETWORKS = [
  { chain: mezoTestnet, label: "Testnet", sub: "Mezo Testnet", tone: "amber" as const },
  { chain: mezoMainnet, label: "Mainnet", sub: "Mezo", tone: "green" as const },
];

function Dot({ tone }: { tone: "amber" | "green" }) {
  return (
    <span
      className="w-2 h-2 rounded-full flex-shrink-0"
      style={{
        background: tone === "green" ? "var(--green)" : "var(--amber)",
        boxShadow: `0 0 0 3px ${tone === "green" ? "rgba(22,163,74,0.16)" : "rgba(217,119,6,0.16)"}`,
      }}
    />
  );
}

interface Props {
  /** Render full-width inside the mobile drawer */
  block?: boolean;
}

export function NetworkSwitcher({ block = false }: Props) {
  const chainId = useChainId();
  const { switchChain, isPending } = useSwitchChain();
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  const active = NETWORKS.find((n) => n.chain.id === chainId) ?? NETWORKS[0];

  useEffect(() => {
    if (!open) return;
    function onClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false);
    }
    document.addEventListener("mousedown", onClick);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onClick);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  function select(id: number) {
    if (id !== chainId) switchChain({ chainId: id });
    setOpen(false);
  }

  return (
    <div ref={ref} className={`relative ${block ? "w-full" : ""}`}>
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-label={`Network: ${active.sub}. Tap to switch network`}
        className={`tap btn-ghost flex items-center gap-2 h-11 rounded-2xl text-sm font-medium cursor-pointer ${
          block ? "w-full justify-between px-4" : "px-3"
        }`}
      >
        <span className="flex items-center gap-2 min-w-0">
          {isPending ? (
            <Loader2 className="w-4 h-4 animate-spin" style={{ color: "var(--text-3)" }} />
          ) : (
            <Dot tone={active.tone} />
          )}
          <span className="truncate" style={{ color: "var(--text)" }}>
            {active.label}
          </span>
        </span>
        <ChevronDown
          className="w-4 h-4 flex-shrink-0 transition-transform duration-200"
          style={{ color: "var(--text-3)", transform: open ? "rotate(180deg)" : "none" }}
        />
      </button>

      {open && (
        <div
          role="listbox"
          className={`animate-pop glass absolute z-50 mt-2 overflow-hidden rounded-2xl ${
            block ? "left-0 right-0" : "right-0 min-w-[14rem]"
          }`}
          style={{ padding: 6 }}
        >
          {NETWORKS.map((n) => {
            const selected = n.chain.id === chainId;
            return (
              <button
                key={n.chain.id}
                type="button"
                role="option"
                aria-selected={selected}
                onClick={() => select(n.chain.id)}
                className="tap w-full flex items-center justify-between gap-3 px-3 min-h-[48px] rounded-xl text-left cursor-pointer transition-colors"
                style={{ background: selected ? "var(--red-bg)" : "transparent" }}
                onMouseEnter={(e) => {
                  if (!selected) e.currentTarget.style.background = "var(--surface)";
                }}
                onMouseLeave={(e) => {
                  if (!selected) e.currentTarget.style.background = "transparent";
                }}
              >
                <span className="flex items-center gap-2.5 min-w-0">
                  <Dot tone={n.tone} />
                  <span className="min-w-0">
                    <span
                      className="block text-sm font-semibold leading-tight truncate"
                      style={{ color: selected ? "var(--red)" : "var(--text)" }}
                    >
                      {n.label}
                    </span>
                    <span className="block text-xs leading-tight truncate" style={{ color: "var(--text-3)" }}>
                      {n.sub}
                    </span>
                  </span>
                </span>
                {selected && <Check className="w-4 h-4 flex-shrink-0" style={{ color: "var(--red)" }} />}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}
