export function WrongNetworkButton({ onClick }: { onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="cursor-pointer text-sm font-medium px-4 py-1.5 rounded-md"
      style={{ background: "#FEF2F2", color: "#DC2626", border: "1px solid #FECACA" }}
    >
      Wrong network
    </button>
  );
}
