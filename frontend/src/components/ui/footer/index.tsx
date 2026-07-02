"use client";

import { useChainId } from "wagmi";

export function Footer() {
  const chainId = useChainId();
  const isMainnet = chainId === 31612;

  return (
    <footer className="pt-2 pb-[max(env(safe-area-inset-bottom),1rem)]">
      <p
        className="flex flex-wrap items-center justify-center gap-x-2 gap-y-1 text-center text-xs"
        style={{ color: "var(--text-3)" }}
      >
        <span className="inline-flex items-center gap-1.5">
          <span
            className="w-1.5 h-1.5 rounded-full"
            style={{ background: isMainnet ? "var(--green)" : "var(--amber)" }}
          />
          Mezo {isMainnet ? "Mainnet" : "Testnet"}
        </span>
        {!isMainnet && (
          <>
            <span aria-hidden>·</span>
            <a
              href="https://faucet.test.mezo.org"
              target="_blank"
              rel="noreferrer"
              className="tap link-muted"
            >
              Get test tokens
            </a>
          </>
        )}
        <span aria-hidden>·</span>
        <a
          href="https://mezo.org/docs"
          target="_blank"
          rel="noreferrer"
          className="tap link-muted"
        >
          Docs
        </a>
      </p>
    </footer>
  );
}
