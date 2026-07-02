"use client";

import { useState, useEffect } from "react";
import {
  useWriteContract,
  useWaitForTransactionReceipt,
  useReadContract,
  useAccount,
  useChainId,
  usePublicClient,
} from "wagmi";
import { parseUnits, maxUint256 } from "viem";
import { VAULT_ABI, ERC20_ABI } from "@/lib/contracts";
import { explorerTxUrl } from "@/lib/utils";

/** Turn an unknown thrown value into a short, human-friendly message. */
function friendlyError(err: unknown): string {
  const raw =
    (typeof err === "object" && err && "shortMessage" in err
      ? String((err as { shortMessage?: unknown }).shortMessage)
      : err instanceof Error
        ? err.message
        : String(err)) || "";
  const lower = raw.toLowerCase();
  if (lower.includes("user rejected") || lower.includes("user denied"))
    return "You rejected the request in your wallet.";
  if (lower.includes("insufficient funds"))
    return "Insufficient funds to cover the transaction and gas.";
  if (lower.includes("exceeds") && lower.includes("balance"))
    return "Amount exceeds your available balance.";
  if (lower.includes("slippage"))
    return "Price moved too much (slippage). Try again.";
  // First sentence only — keep it readable.
  const firstLine = raw.split("\n")[0]?.trim();
  return firstLine && firstLine.length < 140
    ? firstLine
    : "The transaction could not be completed.";
}

export type Tab = "deposit" | "withdraw";
export type DepositToken = "MUSD" | "BTC";
export type TxState = "idle" | "approving" | "pending" | "success" | "error";

interface Params {
  vaultAddress: `0x${string}`;
  tab: Tab;
  depositToken: DepositToken;
  amount: string;
  decimals0: number;
  decimals1: number;
  allowance0: bigint | undefined;
  allowance1: bigint | undefined;
  token0Address: `0x${string}` | undefined;
  token1Address: `0x${string}` | undefined;
  symbol0: string;
  symbol1: string;
  vaultSymbol: string;
  initialized: boolean;
  paused: boolean | undefined;
  isConnected: boolean;
  maxAmount: bigint | undefined;
}

export function useVaultActions({
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
}: Params) {
  const { address } = useAccount();
  const chainId = useChainId();
  const [txState, setTxState] = useState<TxState>("idle");
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();
  const [errorMessage, setErrorMessage] = useState<string | undefined>();

  const publicClient = usePublicClient();
  const { writeContractAsync } = useWriteContract();
  const {
    isLoading: isTxPending,
    isSuccess: isTxSuccess,
    isError: isTxError,
    error: txReceiptError,
  } = useWaitForTransactionReceipt({ hash: txHash });

  // Reset txState when receipt resolves — success or revert
  useEffect(() => {
    if (isTxSuccess) {
      setTxState("success");
    }
    if (isTxError) {
      console.error("On-chain transaction reverted:", txReceiptError);
      setErrorMessage(
        "The transaction was submitted but reverted on-chain. No funds were moved.",
      );
      setTxState("error");
    }
  }, [isTxSuccess, isTxError, txReceiptError]);

  const isToken0 = tab === "withdraw" || depositToken === "MUSD";
  const inputDecimals = isToken0 ? decimals0 : decimals1;

  let amountBig: bigint | undefined = parseUnits(amount, inputDecimals);

  let inputSymbol: string;
  if (tab === "withdraw") inputSymbol = "Shares";
  else if (depositToken === "MUSD") inputSymbol = symbol0;
  else inputSymbol = symbol1;

  // Deposit preview → shares received. Withdraw preview → token0 received.
  const previewSuffix = tab === "deposit" ? vaultSymbol : symbol0;

  // ── Preview (live read, no gas) ────────────────────────────────────────────

  let previewFn: "previewRedeem" | "previewDeposit" | "previewDepositToken1" =
    "previewDepositToken1";
  if (tab === "withdraw") previewFn = "previewRedeem";
  else if (depositToken === "MUSD") previewFn = "previewDeposit";

  const { data: previewResult } = useReadContract({
    address: vaultAddress,
    abi: VAULT_ABI,
    functionName: previewFn,
    args: amountBig ? [amountBig] : undefined,
    query: { enabled: !!amountBig },
  });

  const isDepositingMUSD = tab === "deposit" && depositToken === "MUSD";
  const allowance = isDepositingMUSD ? allowance0 : allowance1;
  const tokenAddress = isDepositingMUSD ? token0Address : token1Address;

  const needsApproval =
    tab === "deposit" &&
    amountBig !== undefined &&
    allowance !== undefined &&
    allowance < amountBig;

  const exceedsMax =
    amountBig !== undefined &&
    amountBig > BigInt(0) &&
    maxAmount !== undefined &&
    amountBig > maxAmount;

  const isProcessing =
    txState === "approving" || txState === "pending" || isTxPending;
  const isDisabled =
    !isConnected || paused || !amountBig || exceedsMax || isProcessing;

  const blockingMessage = paused
    ? "The vault is paused. No deposits or withdrawals at this time."
    : !initialized && tab === "deposit"
      ? "Vault has not opened its first position yet."
      : null;

  async function handleAction() {
    if (!amountBig || !address) return;
    setErrorMessage(undefined);
    setTxHash(undefined);
    try {
      let hash: `0x${string}` | undefined;

      // Auto-approve before deposit if allowance is insufficient
      if (needsApproval && tokenAddress) {
        setTxState("approving");
        const approveHash = await writeContractAsync({
          address: tokenAddress,
          abi: ERC20_ABI,
          functionName: "approve",
          args: [vaultAddress, maxUint256],
        });
        await publicClient?.waitForTransactionReceipt({ hash: approveHash });
      }

      setTxState("pending");

      switch (tab) {
        case "deposit":
          switch (depositToken) {
            case "MUSD":
              await publicClient?.simulateContract({
                address: vaultAddress,
                abi: VAULT_ABI,
                functionName: "deposit",
                args: [amountBig, address],
                account: address,
              });
              hash = await writeContractAsync({
                address: vaultAddress,
                abi: VAULT_ABI,
                functionName: "deposit",
                args: [amountBig, address],
              });
              break;
            default:
              hash = await writeContractAsync({
                address: vaultAddress,
                abi: VAULT_ABI,
                functionName: "depositToken1",
                args: [amountBig, address],
              });
          }
          break;
        case "withdraw":
          hash = await writeContractAsync({
            address: vaultAddress,
            abi: VAULT_ABI,
            functionName: "redeem",
            args: [amountBig, address, address],
          });
          break;
      }

      if (hash) setTxHash(hash);
    } catch (err) {
      console.error("Transaction failed:", err);
      setErrorMessage(friendlyError(err));
      setTxState("error");
    }
  }

  function dismissStatus() {
    setTxState("idle");
    setErrorMessage(undefined);
  }

  const txUrl = txHash ? explorerTxUrl(chainId, txHash) : undefined;

  return {
    // Derived input
    amountBig,
    inputDecimals,
    inputSymbol,
    previewResult: previewResult as bigint | undefined,
    previewSuffix,
    // State
    txState,
    txHash,
    txUrl,
    errorMessage,
    isProcessing,
    isDisabled,
    exceedsMax,
    needsApproval,
    blockingMessage,
    // Handlers
    handleAction,
    dismissStatus,
  };
}
