"use client";

import { Header } from "@/components/ui/header";
import { VaultStats } from "@/components/VaultStats";
import { DepositWithdraw } from "@/components/DepositWithdraw";
import { PriceRangeCard } from "@/components/PriceRangeCard";
import { UserPosition } from "@/components/UserPosition";
import { RebalanceHistory } from "@/components/RebalanceHistory";
import { Footer } from "@/components/ui/footer";
import { useVaultPage } from "@/hooks/useVaultPage";


export default function Home() {
  const {
    isConnected,
    sym0,
    sym1,
    vaultSymbol,
    d0,
    d1,
    vault,
    pool,
    user,
    events,
    apy,
    rebalanceCount,
    totalFee0,
    tickLower,
    tickUpper,
  } = useVaultPage();

  return (
    <div className="min-h-screen bg-white">
      <Header />

      <main className="max-w-5xl mx-auto px-5 py-8 space-y-6">
        <div>
          <h1
            className="text-2xl font-semibold tracking-tight"
            style={{ color: "var(--text)" }}
          >
            {sym0} / {sym1} Vault
          </h1>
          <p className="mt-1 text-sm" style={{ color: "var(--text-2)" }}>
            Deposit tokens and earn trading fees automatically.
          </p>
        </div>

        {/* Stats — full width */}
        <VaultStats
          totalAssets={vault.totalAssets}
          sharePrice={vault.sharePrice}
          performanceFeeBps={vault.performanceFeeBps}
          paused={vault.paused}
          decimals0={d0}
          symbol0={sym0}
          isLoading={vault.isLoading}
          apy={apy}
          rebalanceCount={rebalanceCount}
          totalFee0={totalFee0}
          tickLower={tickLower}
          tickUpper={tickUpper}
        />

        {/* 2-column layout */}
        <div className="grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-6 items-start">
          {/* Left: Deposit/Withdraw + Price Range (renders second on mobile) */}
          <div className="space-y-6 order-2 lg:order-1">
            <DepositWithdraw
              paused={vault.paused}
              initialized={vault.initialized}
              token0Address={vault.token0Address}
              token1Address={vault.token1Address}
              decimals0={d0}
              decimals1={d1}
              symbol0={sym0}
              symbol1={sym1}
              vaultSymbol={vaultSymbol}
              balance0={user.balance0}
              balance1={user.balance1}
              allowance0={user.allowance0}
              allowance1={user.allowance1}
              maxRedeem={user.maxRedeem}
              isConnected={isConnected}
            />
            <PriceRangeCard
              initialized={vault.initialized}
              currentTick={pool.currentTick}
              tickLower={pool.tickLower}
              tickUpper={pool.tickUpper}
              isOutOfRange={pool.isOutOfRange}
              decimals0={d0}
              decimals1={d1}
              symbol0={sym0}
              symbol1={sym1}
            />
          </div>

          {/* Right: User position + History (renders first on mobile) */}
          <div className="space-y-6 order-1 lg:order-2">
            <UserPosition
              shares={user.shares}
              symbol0={sym0}
              decimals0={d0}
              isConnected={isConnected}
            />
            <RebalanceHistory
              rebalances={events.rebalances}
              isLoading={events.isLoading}
              decimals0={d0}
              decimals1={d1}
              symbol0={sym0}
              symbol1={sym1}
            />
          </div>
        </div>

        <Footer />
      </main>
    </div>
  );
}
