export function ConnectWalletButton({ onClick }: { onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="btn-red cursor-pointer text-sm font-medium px-4 min-h-[44px] rounded-md"
    >
      Connect Wallet
    </button>
  );
}

export function WrongNetworkButton({ onClick }: { onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="cursor-pointer text-sm font-medium px-4 min-h-[44px] rounded-md"
      style={{ background: "var(--red-bg)", color: "var(--error)", border: "1px solid var(--red-border)" }}
    >
      Wrong network
    </button>
  );
}
