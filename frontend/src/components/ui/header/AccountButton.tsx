interface AccountButtonProps {
  displayName: string;
  onClick: () => void;
}

export function AccountButton({ displayName, onClick }: AccountButtonProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex items-center gap-1.5 cursor-pointer text-xs font-medium px-3 py-1.5 rounded-md transition-colors"
      style={{
        background: "var(--surface)",
        color: "var(--text)",
        border: "1px solid var(--border)",
        fontFamily: "var(--font-plex-mono), monospace",
      }}
      onMouseEnter={(e) =>
        (e.currentTarget.style.borderColor = "var(--red-border)")
      }
      onMouseLeave={(e) =>
        (e.currentTarget.style.borderColor = "var(--border)")
      }
    >
      {displayName}
    </button>
  );
}
