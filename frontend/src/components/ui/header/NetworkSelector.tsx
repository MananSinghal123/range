"use client";

import { useChainId, useSwitchChain } from "wagmi";

const TESTNET_ID = 31611;
const MAINNET_ID = 31612;

const networks = [
  { id: TESTNET_ID, label: "Testnet" },
  { id: MAINNET_ID, label: "Mainnet" },
];

export function NetworkSelector() {
  const chainId = useChainId();
  const { switchChain, isPending } = useSwitchChain();

  return (
    <div
      className="flex items-center rounded-md overflow-hidden text-xs font-medium"
      style={{
        border: "1px solid var(--border)",
        background: "var(--surface)",
      }}
    >
      {networks.map((network, i) => {
        const isActive = chainId === network.id;
        return (
          <button
            key={network.id}
            type="button"
            onClick={() => !isActive && switchChain({ chainId: network.id })}
            disabled={isPending || isActive}
            className="px-2.5 py-1.5 transition-colors disabled:cursor-default"
            style={{
              background: isActive ? "var(--red-bg)" : "transparent",
              color: isActive ? "var(--red)" : "var(--text-2)",
              borderRight: i === 0 ? "1px solid var(--border)" : undefined,
              cursor: isActive ? "default" : "pointer",
            }}
            onMouseEnter={(e) => {
              if (!isActive) e.currentTarget.style.color = "var(--text)";
            }}
            onMouseLeave={(e) => {
              if (!isActive) e.currentTarget.style.color = "var(--text-2)";
            }}
          >
            {network.label}
          </button>
        );
      })}
    </div>
  );
}
