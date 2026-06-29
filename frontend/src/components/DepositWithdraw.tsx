"use client";

import { useState } from "react";
import { formatUnits } from "viem";
import { Loader2, Check, ChevronDown } from "lucide-react";
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

  const amountInputId = "deposit-withdraw-amount";

  function tabStyle(t: Tab) {
    const active = tab === t;
    return {
      color: active ? "var(--text)" : "var(--text-3)",
      borderBottom: active ? "2px solid var(--red)" : "2px solid transparent",
      marginBottom: "-1px",
      background: "transparent",
    };
  }

  return (
    <div
      className="rounded-xl"
      style={{ border: "1px solid var(--border)", background: "#fff" }}
    >
      {/* Tab switcher */}
      <div className="flex" style={{ borderBottom: "1px solid var(--border)" }}>
        <button
          type="button"
          onClick={() => {
            setTab("deposit");
            setAmount("");
          }}
          className="flex-1 py-3 text-sm font-medium capitalize cursor-pointer"
          style={tabStyle("deposit")}
        >
          Deposit
        </button>
        <button
          type="button"
          onClick={() => {
            setTab("withdraw");
            setAmount("");
          }}
          className="flex-1 py-3 text-sm font-medium capitalize cursor-pointer"
          style={tabStyle("withdraw")}
        >
          Withdraw
        </button>
      </div>

      <div className="p-5 space-y-4">
        {/* Amount input */}
        <div
          className="rounded-lg p-3.5"
          style={{
            background: "var(--surface)",
            border: "1px solid var(--border)",
          }}
          onFocus={(e) =>
            (e.currentTarget.style.borderColor = "var(--border-focus)")
          }
          onBlur={(e) => (e.currentTarget.style.borderColor = "var(--border)")}
        >
          <div className="flex items-center justify-between mb-2">
            <label htmlFor={amountInputId} className="label">
              Amount
            </label>
            {maxAmount !== undefined && (
              <button
                type="button"
                onClick={() =>
                  setAmount(formatUnits(maxAmount, actions.inputDecimals))
                }
                className="label cursor-pointer px-1.5 py-1 -my-1 -mr-1.5"
                style={{ color: "var(--red)" }}
              >
                Max {formatTokenAmount(maxAmount, actions.inputDecimals, 6)}
              </button>
            )}
          </div>
          <div className="flex items-baseline gap-2">
            <input
              id={amountInputId}
              type="number"
              inputMode="decimal"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="0"
              disabled={actions.isProcessing}
              className="flex-1 bg-transparent font-mono text-3xl font-medium outline-none disabled:opacity-40"
              style={{ color: "var(--text)", minWidth: 0 }}
            />
            {tab === "deposit" ? (
              <div className="relative flex-shrink-0">
                <button
                  type="button"
                  onClick={() => setTokenMenuOpen((o) => !o)}
                  aria-haspopup="listbox"
                  aria-expanded={tokenMenuOpen}
                  className="flex items-center gap-1 px-2.5 py-1.5 rounded-md text-sm font-medium cursor-pointer transition-colors"
                  style={{
                    background: "var(--surface)",
                    border: "1px solid var(--border)",
                    color: "var(--text)",
                  }}
                >
                  {actions.inputSymbol}
                  <ChevronDown
                    className="w-3.5 h-3.5 transition-transform"
                    style={{
                      color: "var(--text-3)",
                      transform: tokenMenuOpen ? "rotate(180deg)" : "none",
                    }}
                  />
                </button>

                {tokenMenuOpen && (
                  <>
                    {/* Click-outside backdrop */}
                    <div
                      className="fixed inset-0 z-10"
                      onClick={() => setTokenMenuOpen(false)}
                    />
                    <div
                      role="listbox"
                      className="absolute right-0 top-full mt-1.5 z-20 min-w-[7rem] rounded-lg overflow-hidden"
                      style={{
                        background: "#fff",
                        border: "1px solid var(--border)",
                        boxShadow: "0 8px 24px rgba(0,0,0,0.08)",
                      }}
                    >
                      {(
                        [
                          { key: "MUSD" as DepositToken, label: symbol0 },
                          { key: "BTC" as DepositToken, label: symbol1 },
                        ]
                      ).map(({ key, label }) => {
                        const active = depositToken === key;
                        return (
                          <button
                            key={key}
                            type="button"
                            role="option"
                            aria-selected={active}
                            onClick={() => selectToken(key)}
                            className="w-full text-left px-3 min-h-[44px] text-sm font-medium cursor-pointer transition-colors"
                            style={{
                              background: active
                                ? "var(--red-bg)"
                                : "transparent",
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
                className="text-sm font-medium flex-shrink-0"
                style={{ color: "var(--text-2)" }}
              >
                {actions.inputSymbol}
              </span>
            )}
          </div>
        </div>

        {/* Preview: "You receive X shares / MUSD" */}
        {actions.amountBig && actions.previewResult !== undefined && (
          <div className="flex items-center justify-between">
            <span className="label">You receive</span>
            <span className="mono text-sm" style={{ color: "var(--text)" }}>
              {formatTokenAmount(actions.previewResult, decimals0, 8)}{" "}
              {actions.previewSuffix}
            </span>
          </div>
        )}

        {/* Vault blocking message (paused / not initialized) */}
        {actions.blockingMessage && (
          <p className="text-sm" style={{ color: "var(--text-2)" }}>
            {actions.blockingMessage}
          </p>
        )}

        {/* Over-limit warning */}
        {actions.exceedsMax && (
          <p className="text-sm" style={{ color: "var(--error)" }}>
            {tab === "withdraw"
              ? "Amount exceeds your redeemable shares"
              : `Amount exceeds your ${actions.inputSymbol} balance`}
          </p>
        )}

        {/* Transaction status */}
        {actions.txState === "success" && (
          <p
            className="text-sm font-medium flex items-center gap-1.5"
            style={{ color: "var(--green)" }}
          >
            <Check className="w-4 h-4 flex-shrink-0" /> Transaction confirmed
          </p>
        )}
        {actions.txState === "error" && (
          <p className="text-sm" style={{ color: "var(--error)" }}>
            Transaction failed — please try again
          </p>
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
            className="btn-red w-full py-3 rounded-lg text-sm font-semibold flex items-center justify-center gap-2 cursor-pointer"
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
          <p
            className="text-center"
            style={{ fontSize: "12px", color: "var(--text-3)" }}
          >
            You receive both {symbol0} and {symbol1} proportionally
          </p>
        )}
      </div>
    </div>
  );
}
