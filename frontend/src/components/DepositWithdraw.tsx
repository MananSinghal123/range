"use client";

import { useState } from "react";
import { formatUnits } from "viem";
import { Loader2 } from "lucide-react";
import { formatTokenAmount } from "@/lib/utils";
import { useVaultActions, type Tab, type DepositToken } from "@/hooks/useVaultActions";

interface Props {
  paused?: boolean;
  initialized: boolean;
  token0Address?: `0x${string}`;
  token1Address?: `0x${string}`;
  decimals0?: number;
  decimals1?: number;
  symbol0?: string;
  symbol1?: string;
  balance0?: bigint;
  balance1?: bigint;
  allowance0?: bigint;
  allowance1?: bigint;
  maxRedeem?: bigint;
  isConnected: boolean;
}

export function DepositWithdraw({
  paused,
  initialized,
  token0Address,
  token1Address,
  decimals0 = 18,
  decimals1 = 8,
  symbol0 = "MUSD",
  symbol1 = "BTC",
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

  const actions = useVaultActions({
    tab, depositToken, amount,
    decimals0, decimals1,
    allowance0, allowance1,
    token0Address, token1Address,
    symbol0, symbol1,
    initialized, paused, isConnected,
  });

  const balance =
    tab === "withdraw" ? maxRedeem :
    depositToken === "MUSD" ? balance0 : balance1;

  function tabStyle(t: Tab) {
    const active = tab === t;
    return {
      color: active ? "var(--text)" : "var(--text-3)",
      borderBottom: active ? "2px solid var(--red)" : "2px solid transparent",
      marginBottom: "-1px",
      background: "transparent",
    };
  }

  function tokenBtnStyle(dt: DepositToken) {
    const active = depositToken === dt;
    return {
      background: active ? "var(--red-bg)" : "var(--surface)",
      color: active ? "var(--red)" : "var(--text-2)",
      border: `1px solid ${active ? "var(--red-border)" : "var(--border)"}`,
    };
  }

  return (
    <div className="rounded-xl" style={{ border: "1px solid var(--border)", background: "#fff" }}>

      {/* Tab switcher */}
      <div className="flex" style={{ borderBottom: "1px solid var(--border)" }}>
        <button type="button" onClick={() => { setTab("deposit"); setAmount(""); }}
          className="flex-1 py-3 text-sm font-medium capitalize cursor-pointer" style={tabStyle("deposit")}>
          Deposit
        </button>
        <button type="button" onClick={() => { setTab("withdraw"); setAmount(""); }}
          className="flex-1 py-3 text-sm font-medium capitalize cursor-pointer" style={tabStyle("withdraw")}>
          Withdraw
        </button>
      </div>

      <div className="p-5 space-y-4">

        {/* Token selector (deposit only) */}
        {tab === "deposit" && (
          <div className="flex gap-2">
            <button type="button" onClick={() => { setDepositToken("MUSD"); setAmount(""); }}
              className="px-3 py-1.5 rounded-md text-sm font-medium cursor-pointer" style={tokenBtnStyle("MUSD")}>
              {symbol0}
            </button>
            <button type="button" onClick={() => { setDepositToken("BTC"); setAmount(""); }}
              className="px-3 py-1.5 rounded-md text-sm font-medium cursor-pointer" style={tokenBtnStyle("BTC")}>
              {symbol1}
            </button>
          </div>
        )}

        {/* Amount input */}
        <div className="rounded-lg p-3.5"
          style={{ background: "var(--surface)", border: "1px solid var(--border)" }}
          onFocus={(e) => (e.currentTarget.style.borderColor = "var(--border-focus)")}
          onBlur={(e) => (e.currentTarget.style.borderColor = "var(--border)")}>
          <div className="flex items-center justify-between mb-2">
            <span className="label">Amount</span>
            {balance !== undefined && (
              <button type="button" onClick={() => setAmount(formatUnits(balance, actions.inputDecimals))}
                className="label cursor-pointer" style={{ color: "var(--red)" }}>
                Max {formatTokenAmount(balance, actions.inputDecimals, 6)}
              </button>
            )}
          </div>
          <div className="flex items-baseline gap-2">
            <input
              type="number"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="0"
              disabled={actions.isProcessing}
              className="flex-1 bg-transparent font-mono text-3xl font-medium outline-none disabled:opacity-40"
              style={{ color: "var(--text)", minWidth: 0 }}
            />
            <span className="text-sm font-medium flex-shrink-0" style={{ color: "var(--text-2)" }}>
              {actions.inputSymbol}
            </span>
          </div>
        </div>

        {/* Preview: "You receive X shares / MUSD" */}
        {actions.amountBig && actions.previewResult !== undefined && (
          <div className="flex items-center justify-between">
            <span className="label">You receive</span>
            <span className="mono text-sm" style={{ color: "var(--text)" }}>
              {formatTokenAmount(actions.previewResult, decimals0, 8)} {actions.previewSuffix}
            </span>
          </div>
        )}

        {/* Vault blocking message (paused / not initialized) */}
        {actions.blockingMessage && (
          <p className="text-sm" style={{ color: "var(--text-2)" }}>{actions.blockingMessage}</p>
        )}

        {/* Transaction status */}
        {actions.txState === "success" && (
          <p className="text-sm font-medium" style={{ color: "var(--green)" }}>✓ Transaction confirmed</p>
        )}
        {actions.txState === "error" && (
          <p className="text-sm" style={{ color: "#DC2626" }}>Transaction failed — please try again</p>
        )}

        {/* Action button */}
        {!isConnected && (
          <p className="text-sm text-center" style={{ color: "var(--text-3)" }}>Connect your wallet to continue</p>
        )}

        {isConnected && actions.needsApproval && (
          <button type="button" onClick={actions.handleApprove} disabled={actions.isProcessing}
            className="btn-red w-full py-3 rounded-lg text-sm font-semibold flex items-center justify-center gap-2 cursor-pointer">
            {actions.isProcessing
              ? <><Loader2 className="w-4 h-4 animate-spin" /> Approving…</>
              : `Allow ${actions.inputSymbol}`}
          </button>
        )}

        {isConnected && !actions.needsApproval && (
          <button type="button" onClick={actions.handleAction} disabled={actions.isDisabled}
            className="btn-red w-full py-3 rounded-lg text-sm font-semibold flex items-center justify-center gap-2 cursor-pointer">
            {actions.isProcessing
              ? <><Loader2 className="w-4 h-4 animate-spin" /> Confirming…</>
              : tab === "deposit" ? `Deposit ${actions.inputSymbol}` : "Withdraw"}
          </button>
        )}

        {tab === "withdraw" && isConnected && (
          <p className="text-center" style={{ fontSize: "12px", color: "var(--text-3)" }}>
            You receive both {symbol0} and {symbol1} proportionally
          </p>
        )}

      </div>
    </div>
  );
}
