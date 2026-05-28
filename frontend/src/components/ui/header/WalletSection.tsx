"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";
import { NetworkSelector } from "./NetworkSelector";
import { AccountButton } from "./AccountButton";
import { ConnectWalletButton } from "./ConnectWalletButton";
import { WrongNetworkButton } from "./WrongNetworkButton";

export function WalletSection() {
  return (
    <ConnectButton.Custom>
      {({ account, chain, openAccountModal, openChainModal, openConnectModal, authenticationStatus, mounted }) => {
        const ready = mounted && authenticationStatus !== "loading";
        const connected =
          ready &&
          account &&
          chain &&
          (!authenticationStatus || authenticationStatus === "authenticated");

        if (!ready) return <div style={{ width: 120, height: 32 }} />;
        if (!connected) return <ConnectWalletButton onClick={openConnectModal} />;
        if (chain.unsupported) return <WrongNetworkButton onClick={openChainModal} />;

        return (
          <div className="flex items-center gap-2">
            <NetworkSelector />
            <AccountButton displayName={account.displayName} onClick={openAccountModal} />
          </div>
        );
      }}
    </ConnectButton.Custom>
  );
}
