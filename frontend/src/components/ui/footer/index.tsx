export function Footer() {
  return (
    <p className="text-center" style={{ fontSize: "12px", color: "var(--text-3)" }}>
      Mezo Testnet ·{" "}
      <a
        href="https://faucet.test.mezo.org"
        target="_blank"
        rel="noreferrer"
        style={{ color: "var(--text-3)" }}
        onMouseEnter={(e) => (e.currentTarget.style.color = "var(--red)")}
        onMouseLeave={(e) => (e.currentTarget.style.color = "var(--text-3)")}
      >
        Get test tokens
      </a>{" "}·{" "}
      <a
        href="https://mezo.org/docs"
        target="_blank"
        rel="noreferrer"
        style={{ color: "var(--text-3)" }}
        onMouseEnter={(e) => (e.currentTarget.style.color = "var(--red)")}
        onMouseLeave={(e) => (e.currentTarget.style.color = "var(--text-3)")}
      >
        Docs
      </a>
    </p>
  );
}
