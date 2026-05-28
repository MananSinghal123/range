export function ConnectWalletButton({ onClick }: { onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="cursor-pointer text-sm font-medium px-4 py-1.5 rounded-md transition-colors"
      style={{ background: "var(--red)", color: "#fff" }}
      onMouseEnter={(e) => (e.currentTarget.style.background = "var(--red-dark)")}
      onMouseLeave={(e) => (e.currentTarget.style.background = "var(--red)")}
    >
      Connect Wallet
    </button>
  );
}
