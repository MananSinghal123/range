"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";
import { Wallet } from "lucide-react";

import { ConnectWalletButton, WrongNetworkButton } from "./utils";

interface Props {
  /** Render the account control full-width (used inside the mobile drawer) */
  block?: boolean;
}

export function WalletSection({ block = false }: Props) {
  return (
    <ConnectButton.Custom>
      {({
        account,
        chain,
        openAccountModal,
        openChainModal,
        openConnectModal,
        authenticationStatus,
        mounted,
      }) => {
        const ready = mounted && authenticationStatus !== "loading";
        const connected =
          ready &&
          account &&
          chain &&
          (!authenticationStatus || authenticationStatus === "authenticated");

        return (
          <div
            className={block ? "w-full" : ""}
            {...(!ready && {
              "aria-hidden": true,
              style: { opacity: 0, pointerEvents: "none", userSelect: "none" },
            })}
          >
            {(() => {
              if (!connected)
                return (
                  <ConnectWalletButton onClick={openConnectModal} block={block} />
                );
              if (chain.unsupported)
                return <WrongNetworkButton onClick={openChainModal} block={block} />;
              return (
                <button
                  onClick={openAccountModal}
                  type="button"
                  aria-label="Open account"
                  className={`tap btn-ghost flex items-center gap-2 h-11 px-3 rounded-2xl text-sm font-medium cursor-pointer ${
                    block ? "w-full justify-center" : ""
                  }`}
                >
                  <span
                    className="flex items-center justify-center w-6 h-6 rounded-full flex-shrink-0"
                    style={{ background: "var(--red-bg)" }}
                  >
                    <Wallet className="w-3.5 h-3.5" style={{ color: "var(--red)" }} />
                  </span>
                  <span className="truncate" style={{ color: "var(--text)" }}>
                    {account.displayName}
                  </span>
                  {account.displayBalance && (
                    <span
                      className="mono text-xs hidden sm:inline"
                      style={{ color: "var(--text-3)" }}
                    >
                      {account.displayBalance}
                    </span>
                  )}
                </button>
              );
            })()}
          </div>
        );
      }}
    </ConnectButton.Custom>
  );
}
