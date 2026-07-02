import { AlertTriangle } from "lucide-react";

export function ConnectWalletButton({
  onClick,
  block = false,
}: {
  onClick: () => void;
  block?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`tap btn-red cursor-pointer text-sm font-semibold px-4 h-11 rounded-2xl ${
        block ? "w-full" : ""
      }`}
    >
      Connect Wallet
    </button>
  );
}

export function WrongNetworkButton({
  onClick,
  block = false,
}: {
  onClick: () => void;
  block?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`tap cursor-pointer flex items-center justify-center gap-1.5 text-sm font-semibold px-4 h-11 rounded-2xl ${
        block ? "w-full" : ""
      }`}
      style={{
        background: "var(--error-bg)",
        color: "var(--error)",
        border: "1px solid var(--error-border)",
      }}
    >
      <AlertTriangle className="w-4 h-4" />
      Wrong network
    </button>
  );
}
