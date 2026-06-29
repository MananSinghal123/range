"use client";

import { useState } from "react";
import { formatUnits } from "viem";
import {
  Loader2,
  CheckCircle2,
  AlertTriangle,
  ChevronDown,
  ArrowUpRight,
  X,
} from "lucide-react";
import { formatTokenAmount } from "@/lib/utils";
import {
  useVaultActions,
  type Tab,
  type DepositToken,
} from "@/hooks/useVaultActions";

interface Props {
  vaultAddress: `0x${string}`;
  paused?: boolean;
  initialized: boolean;
  token0Address?: `0x${string}`;
  token1Address?: `0x${string}`;
  decimals0?: number;
  decimals1?: number;
  symbol0?: string;
  symbol1?: string;
  vaultSymbol?: string;
  balance0?: bigint;
  balance1?: bigint;
  allowance0?: bigint;
  allowance1?: bigint;
  maxRedeem?: bigint;
  isConnected: boolean;
}

export function DepositWithdraw({
  vaultAddress,
  paused,
  initialized,
  token0Address,
  token1Address,
  decimals0 = 18,
  decimals1 = 8,
  symbol0 = "MUSD",
  symbol1 = "BTC",
  vaultSymbol = "mREBAL",
  balance0,
  balance1,
  allowance0,
  allowance1,
  maxRedeem,
  isConnected,
}: Props) {
  const [tab, setTab] = useState<Tab>("deposit");
  const [depositToken, setDepositToken] = useState<DepositToken>("MUSD");
  const [amount, setAmount] = useState("");
  const [tokenMenuOpen, setTokenMenuOpen] = useState(false);

  function selectToken(dt: DepositToken) {
    setDepositToken(dt);
    setAmount("");
    setTokenMenuOpen(false);
  }

  const balance = depositToken === "MUSD" ? balance0 : balance1;
  // Deposit caps at the token balance; withdraw caps at redeemable shares.
  const maxAmount = tab === "withdraw" ? maxRedeem : balance;

  const actions = useVaultActions({
    vaultAddress,
    tab,
    depositToken,
    amount,
    decimals0,
    decimals1,
    allowance0,
    allowance1,
    token0Address,
    token1Address,
    symbol0,
    symbol1,
    vaultSymbol,
    initialized,
    paused,
    isConnected,
    maxAmount,
  });

  function switchTab(t: Tab) {
    setTab(t);
    setAmount("");
    actions.dismissStatus();
  }

  const amountInputId = "deposit-withdraw-amount";

  return (
    <div className="card overflow-hidden animate-in">
      {/* Tab switcher */}
      <div className="flex relative" style={{ borderBottom: "1px solid var(--border)" }}>
        {(["deposit", "withdraw"] as Tab[]).map((t) => {
          const active = tab === t;
          return (
            <button
              key={t}
              type="button"
              onClick={() => switchTab(t)}
              className="relative flex-1 py-3.5 text-sm font-semibold capitalize cursor-pointer tap transition-colors"
              style={{ color: active ? "var(--text)" : "var(--text-3)" }}
            >
              {t}
              <span
                className="absolute left-4 right-4 bottom-0 h-[2.5px] rounded-full transition-opacity duration-200"
                style={{
                  background: "linear-gradient(90deg, #EB2552, var(--red))",
                  opacity: active ? 1 : 0,
                }}
              />
            </button>
          );
        })}
      </div>

      <div className="p-5 space-y-4">
        {/* Amount input */}
        <div
          className="rounded-2xl p-4 transition-all duration-200"
          style={{
            background: "var(--surface)",
            border: "1px solid var(--border)",
          }}
          onFocus={(e) => {
            e.currentTarget.style.borderColor = "var(--border-focus)";
            e.currentTarget.style.boxShadow = "0 0 0 4px rgba(225,29,72,0.08)";
          }}
          onBlur={(e) => {
            e.currentTarget.style.borderColor = "var(--border)";
            e.currentTarget.style.boxShadow = "none";
          }}
        >
          <div className="flex items-center justify-between mb-2">
            <label htmlFor={amountInputId} className="label">
              {tab === "deposit" ? "You deposit" : "You withdraw"}
            </label>
            {maxAmount !== undefined && (
              <button
                type="button"
                onClick={() =>
                  setAmount(formatUnits(maxAmount, actions.inputDecimals))
                }
                className="tap label cursor-pointer px-2 py-1 -my-1 -mr-1 rounded-md transition-colors"
                style={{ color: "var(--red)" }}
              >
                Max {formatTokenAmount(maxAmount, actions.inputDecimals, 6)}
              </button>
            )}
          </div>
          <div className="flex items-center gap-2">
            <input
              id={amountInputId}
              type="number"
              inputMode="decimal"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="0"
              disabled={actions.isProcessing}
              className="flex-1 bg-transparent mono text-[32px] leading-tight font-semibold outline-none disabled:opacity-40"
              style={{ color: "var(--text)", minWidth: 0 }}
            />
            {tab === "deposit" ? (
              <div className="relative flex-shrink-0">
                <button
                  type="button"
                  onClick={() => setTokenMenuOpen((o) => !o)}
                  aria-haspopup="listbox"
                  aria-expanded={tokenMenuOpen}
                  className="tap flex items-center gap-1.5 pl-3 pr-2.5 h-10 rounded-xl text-sm font-semibold cursor-pointer transition-colors"
                  style={{
                    background: "#fff",
                    border: "1px solid var(--border)",
                    color: "var(--text)",
                    boxShadow: "var(--shadow-xs)",
                  }}
                >
                  {actions.inputSymbol}
                  <ChevronDown
                    className="w-4 h-4 transition-transform duration-200"
                    style={{
                      color: "var(--text-3)",
                      transform: tokenMenuOpen ? "rotate(180deg)" : "none",
                    }}
                  />
                </button>

                {tokenMenuOpen && (
                  <>
                    <div
                      className="fixed inset-0 z-10"
                      onClick={() => setTokenMenuOpen(false)}
                    />
                    <div
                      role="listbox"
                      className="animate-pop glass absolute right-0 top-full mt-2 z-20 min-w-[8rem] rounded-2xl overflow-hidden"
                      style={{ padding: 6 }}
                    >
                      {[
                        { key: "MUSD" as DepositToken, label: symbol0 },
                        { key: "BTC" as DepositToken, label: symbol1 },
                      ].map(({ key, label }) => {
                        const active = depositToken === key;
                        return (
                          <button
                            key={key}
                            type="button"
                            role="option"
                            aria-selected={active}
                            onClick={() => selectToken(key)}
                            className="tap w-full text-left px-3 min-h-[44px] rounded-xl text-sm font-semibold cursor-pointer transition-colors"
                            style={{
                              background: active ? "var(--red-bg)" : "transparent",
                              color: active ? "var(--red)" : "var(--text)",
                            }}
                          >
                            {label}
                          </button>
                        );
                      })}
                    </div>
                  </>
                )}
              </div>
            ) : (
              <span
                className="text-sm font-semibold flex-shrink-0 px-3 h-10 flex items-center rounded-xl"
                style={{
                  color: "var(--text-2)",
                  background: "#fff",
                  border: "1px solid var(--border)",
                }}
              >
                {actions.inputSymbol}
              </span>
            )}
          </div>
        </div>

        {/* Preview: "You receive X shares / MUSD" */}
        {actions.amountBig && actions.previewResult !== undefined && (
          <div
            className="flex items-center justify-between px-3.5 py-2.5 rounded-xl"
            style={{ background: "var(--surface)" }}
          >
            <span className="label">You receive</span>
            <span className="mono text-sm font-semibold" style={{ color: "var(--text)" }}>
              {formatTokenAmount(actions.previewResult, decimals0, 8)}{" "}
              {actions.previewSuffix}
            </span>
          </div>
        )}

        {/* Vault blocking message (paused / not initialized) */}
        {actions.blockingMessage && (
          <div
            className="flex items-start gap-2.5 p-3 rounded-xl text-sm"
            style={{ background: "var(--surface)", color: "var(--text-2)" }}
          >
            <AlertTriangle className="w-4 h-4 flex-shrink-0 mt-0.5" style={{ color: "var(--amber)" }} />
            {actions.blockingMessage}
          </div>
        )}

        {/* Over-limit warning */}
        {actions.exceedsMax && (
          <p className="text-sm font-medium flex items-center gap-1.5" style={{ color: "var(--error)" }}>
            <AlertTriangle className="w-4 h-4 flex-shrink-0" />
            {tab === "withdraw"
              ? "Amount exceeds your redeemable shares"
              : `Amount exceeds your ${actions.inputSymbol} balance`}
          </p>
        )}

        {/* ── Transaction status banners ─────────────────────────── */}
        {actions.txState === "success" && (
          <StatusBanner
            tone="success"
            title="Transaction confirmed"
            message="Your transaction was processed successfully."
            txUrl={actions.txUrl}
            onDismiss={actions.dismissStatus}
          />
        )}
        {actions.txState === "error" && (
          <StatusBanner
            tone="error"
            title="Oops — transaction failed"
            message={actions.errorMessage ?? "Something went wrong. Please try again."}
            txUrl={actions.txUrl}
            onDismiss={actions.dismissStatus}
          />
        )}

        {/* Action button */}
        {!isConnected && (
          <p className="text-sm text-center" style={{ color: "var(--text-3)" }}>
            Connect your wallet to continue
          </p>
        )}

        {isConnected && (
          <button
            type="button"
            onClick={actions.handleAction}
            disabled={actions.isDisabled}
            className="tap btn-red w-full py-3.5 rounded-2xl text-[15px] font-semibold flex items-center justify-center gap-2 cursor-pointer"
          >
            {actions.txState === "approving" ? (
              <>
                <Loader2 className="w-4 h-4 animate-spin" /> Approving…
              </>
            ) : actions.txState === "pending" || actions.isProcessing ? (
              <>
                <Loader2 className="w-4 h-4 animate-spin" /> Confirming…
              </>
            ) : tab === "deposit" ? (
              `Deposit ${actions.inputSymbol}`
            ) : (
              "Withdraw"
            )}
          </button>
        )}

        {tab === "withdraw" && isConnected && (
          <p className="text-center text-xs" style={{ color: "var(--text-3)" }}>
            You receive both {symbol0} and {symbol1} proportionally
          </p>
        )}
      </div>
    </div>
  );
}

function StatusBanner({
  tone,
  title,
  message,
  txUrl,
  onDismiss,
}: {
  tone: "success" | "error";
  title: string;
  message: string;
  txUrl?: string;
  onDismiss: () => void;
}) {
  const isSuccess = tone === "success";
  const accent = isSuccess ? "var(--green)" : "var(--error)";
  const bg = isSuccess ? "var(--green-bg)" : "var(--error-bg)";
  const border = isSuccess ? "var(--green-border)" : "var(--error-border)";
  const Icon = isSuccess ? CheckCircle2 : AlertTriangle;

  return (
    <div
      className="animate-pop relative rounded-2xl p-3.5"
      style={{ background: bg, border: `1px solid ${border}` }}
      role={isSuccess ? "status" : "alert"}
      aria-live={isSuccess ? "polite" : "assertive"}
    >
      <button
        type="button"
        onClick={onDismiss}
        aria-label="Dismiss"
        className="tap absolute top-2.5 right-2.5 w-7 h-7 flex items-center justify-center rounded-lg cursor-pointer transition-colors"
        style={{ color: "var(--text-3)" }}
      >
        <X className="w-4 h-4" />
      </button>
      <div className="flex items-start gap-2.5 pr-6">
        <Icon className="w-[18px] h-[18px] flex-shrink-0 mt-0.5" style={{ color: accent }} />
        <div className="min-w-0">
          <p className="text-sm font-semibold" style={{ color: accent }}>
            {title}
          </p>
          <p className="text-[13px] mt-0.5 leading-snug" style={{ color: "var(--text-2)" }}>
            {message}
          </p>
          {txUrl && (
            <a
              href={txUrl}
              target="_blank"
              rel="noreferrer"
              className="tap inline-flex items-center gap-1 mt-2 text-[13px] font-semibold"
              style={{ color: accent }}
            >
              View transaction
              <ArrowUpRight className="w-3.5 h-3.5" />
            </a>
          )}
        </div>
      </div>
    </div>
  );
}
