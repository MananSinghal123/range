# RebalancerVault

[![standard-readme compliant](https://img.shields.io/badge/readme%20style-standard-brightgreen.svg?style=flat-square)](https://github.com/RichardLitt/standard-readme)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.x-blue?style=flat-square)](https://soliditylang.org)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-orange?style=flat-square)](https://getfoundry.sh)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)

An automated concentrated-liquidity rebalancing vault for Mezo's Uniswap V3-compatible DEX. Users deposit tokens and receive ERC-4626 vault shares; an off-chain keeper bot monitors pool prices and rebalances LP positions back into range automatically, compounding fees continuously.

Built for the [Mezo DEX Automated LP Rebalancing Vault Bounty](https://coda.io/d/Mezo-Community-Resources_d7Ee5YHYoEI/Bounty-Automated-LP-Rebalancing-Vault-for-Mezo-DEX_suo_otcs#_luPM-Uue).

## Deployed Contracts (Mezo Testnet)

| Contract         | Address                                      |
| ---------------- | -------------------------------------------- |
| Implementation   | `0x69DE1125e5b3fbdD5e64A3F47803AF761c2e7699` |
| CLDexAdapter     | `0x4403297D0Fbc68B5643418dEe4b2A7606A3fEb16` |
| VaultLens        | `0x96F18Ee1aF466981C50b1E76D7604a652b451Cd0` |
| VaultFactory     | `0x5260ead0f831040Fb14901DDAD758c0110fd3939` |
| Strategy Tight   | `0x79f1E677C3ba8481b7f5B676EaB606AEa7dA8eD5` |
| Strategy Medium  | `0x4f562D8e199a02363a7f4663027CdEEFfB395686` |
| Strategy Wide    | `0x07181Dc9E7538E5CA841B54819a354F3A2900EF9` |
| Vault MUSD/BTC Tight  | `0x9b29b71829597A1B705Ea1Bab1C8B2fD00088594` |
| Vault MUSD/BTC Medium | `0x3f92984091B71862F848452aE49943060C3Fac1A` |
| Vault MUSD/BTC Wide   | `0x4b192b5f56fe5066a8B44dAa2376bE85073f3a3b` |

## Background

Uniswap V3-style concentrated liquidity lets LPs earn higher fees by concentrating capital in a narrow price range, but once the price drifts outside that range the position earns nothing. Retail LPs lack the tools to monitor positions around the clock.

RebalancerVault solves this by acting as a managed fund: depositors mint vault shares backed by a single active LP position. When the price moves out of range, the keeper bot calls `rebalance()` on-chain. The vault removes liquidity, collects and compounds accrued fees, rebalances token ratios via a single swap, and mints a new position centred on the current TWAP — all in one atomic transaction.

A **10% performance fee** on collected trading fees sustains the protocol. Fee changes are gated behind a 2-day timelock.

Range strategy options:

| Strategy | Half-width (ticks) | Best for                                  |
| -------- | ------------------ | ----------------------------------------- |
| TIGHT    | ±300               | Low-volatility pairs, maximum fee capture |
| MEDIUM   | ±700               | Balanced risk/reward (default)            |
| WIDE     | ±1200              | High-volatility pairs, fewer rebalances   |

## Security

RebalancerVault manages user funds. The following mitigations are implemented:

| Vector                                     | Mitigation                                                                                          |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| Reentrancy                                 | OpenZeppelin `ReentrancyGuard` on `deposit`, `withdraw`, `redeem`, `rebalance`                      |
| Price manipulation / flash loans           | All deposits and rebalance ranges anchored to a 5-minute TWAP; reverts if spot deviates > 200 ticks |
| Vault inflation (ERC-4626 first-depositor) | 1 000 dead shares burned into `address(0)` on first deposit                                         |
| Slippage on removeLiquidity / mint / swap  | On-chain TWAP-derived `amountMin` guards — not caller-supplied                                      |
| Unauthorized rebalance                     | `onlyOperator` modifier; keeper wallet set by owner                                                 |
| Fee extraction griefing                    | 2-day timelock on `performanceFee` changes; max 10% (1 000 bps) hard-coded                          |
| Same-block sandwich                        | Block-number guard prevents deposit and withdrawal in the same block                                |
| Emergency                                  | Owner can `setPaused(true)` to halt all deposits, withdrawals, and rebalances                       |
| Ownership handover                         | Two-step `transferOwnership` / `acceptOwnership` pattern                                            |

## Architecture

**Core functions:**

| Function                                          | Access   | Description                      |
| ------------------------------------------------- | -------- | -------------------------------- |
| `deposit(assets, receiver)`                       | Public   | Deposit token0, mint shares      |
| `depositToken1(amount, receiver)`                 | Public   | Deposit token1 (TWAP-converted)  |
| `withdraw(assets, receiver, owner)`               | Public   | Burn shares, receive token0      |
| `redeem(shares, receiver, owner)`                 | Public   | Burn shares, receive both tokens |
| `initializePosition(tickLower, tickUpper, ...)`   | Owner    | Create first LP position (once)  |
| `rebalance(swapZeroForOne, swapAmount, strategy)` | Operator | Trigger a full rebalance         |
| `collectFees(amount0Min, amount1Min)`             | Operator | Collect fees without rebalancing |
| `setPaused(bool)`                                 | Owner    | Emergency pause                  |
| `proposePerformanceFee(bps, recipient)`           | Owner    | Queue fee change (2-day lock)    |
| `applyPerformanceFee()`                           | Owner    | Apply queued fee change          |

**Rebalance execution (6 atomic steps):**

```
vault.rebalance()
  │
  ├─ 1. Remove all liquidity from current position (TWAP-derived amountMin)
  ├─ 2. Collect accrued fees → deduct 10% performance fee → transfer to feeRecipient
  ├─ 3. Burn the old ERC-721 position NFT
  ├─ 4. Swap (token0 ↔ token1) to align ratio for new range (if needed)
  ├─ 5. Compute new range: [floor(twapTick - halfWidth), ceil(twapTick + halfWidth)]
  └─ 6. Mint new LP position with all available tokens → store new tokenId
```

**Key view functions:**

- `isOutOfRange() → bool` — whether to trigger rebalance
- `totalAssets() → uint256` — vault TVL in token0 (position + fees + idle)
- `sharePrice() → uint256` — 1e18-scaled price per share in token0
- `getVaultMetrics()` — batch query: TVL, ticks, rebalance count, fees earned

---

### Keeper Bot

The keeper bot (`keeper-bot/`) is a Node.js service that polls vault state and submits `rebalance()` transactions when the position is out of range.

#### Module Map

```
keeper-bot/
├── index.js        ← entry point; startup, main loop, graceful shutdown
├── rebalancer.js   ← core logic: checkAndRebalance(), computeRebalanceArgs()
├── config.js       ← env-var parsing into a typed Config object
├── provider.js     ← JsonRpcProvider / WebSocketProvider with auto-reconnect
├── state.js        ← per-vault runtime state (failures, counters, timestamps)
├── events.js       ← WebSocket pool Swap listener (event-driven path)
├── logger.js       ← timestamped logInfo / logWarn / logErr
├── errors.js       ← isNetworkError, isRetryableError, jitter()
└── abi/            ← RebalancerVault ABI JSON
```

#### Execution Flow

```
┌──────────────────────────────────────────────────────────────────────┐
│ STARTUP                                                              │
│  1. Parse config (env vars)                                          │
│  2. Init per-vault state (failures=0, totalRebalances=0, …)          │
│  3. Preflight: check keeper wallet ETH balance                       │
│  4. Optionally attach WebSocket Swap listeners (event-driven path)   │
└──────────────────────────────┬───────────────────────────────────────┘
                               │
                    ┌──────────▼──────────┐
                    │   MAIN POLL LOOP    │  every POLL_INTERVAL_MS (default 30 s)
                    │  (also fires on     │
                    │   each Swap event)  │
                    └──────────┬──────────┘
                               │ for each watched vault
                               ▼
                    ┌──────────────────────┐
                    │ checkAndRebalance()  │
                    └──────────┬───────────┘
                               │
              ┌────────────────▼──────────────────────┐
              │ GUARD CHECKS (short-circuit on fail)   │
              │  • nextAttemptAt > now? → skip (backoff)│
              │  • tokenId == 0?        → skip (uninit) │
              │  • isOutOfRange()?      → continue      │
              │    else reset counter   → return        │
              │  • vault.paused?        → skip          │
              │  • gasPrice > MAX?      → skip          │
              └────────────────┬──────────────────────┘
                               │ all checks pass
                               ▼
                    ┌──────────────────────────┐
                    │ computeRebalanceArgs()   │
                    │  • Query pool sqrtPrice  │
                    │  • Query position ticks  │
                    │  • Estimate freed amounts│
                    │  • Compute optimal swap  │
                    │  • Derive new tick range │
                    └──────────┬───────────────┘
                               │
                               ▼
                    ┌──────────────────────────┐
                    │ buildAndSendTx()         │
                    │  gasLimit × 1.2 buffer   │
                    │  signer.sendTransaction()│
                    └──────────┬───────────────┘
                               │
              ┌────────────────┴──────────────────────┐
              │ SUCCESS                   ERROR        │
              │  totalRebalances++    isRetryable?     │
              │  consecutiveFails=0   yes → backoff    │
              │                       no  → log, skip  │
              └───────────────────────────────────────┘
                               │ network errors > 8
                               ▼
                    ┌──────────────────────────┐
                    │ provider.resetProvider() │
                    │ reconnect RPC            │
                    └──────────────────────────┘

                    ┌──────────────────────────┐
                    │ GRACEFUL SHUTDOWN        │
                    │  SIGINT / SIGTERM        │
                    │  remove all listeners    │
                    │  process.exit(0)         │
                    └──────────────────────────┘
```

#### Backoff Strategy

Failed rebalance attempts use **exponential backoff with ±15% jitter** to prevent thundering-herd behaviour on network partitions:

```
delay = min(30s × 2^consecutiveFailures, 5 min) × jitter(0.85–1.15)
```

#### Event-Driven vs Polling

The bot supports two complementary trigger paths:

| Path         | Mechanism                             | Latency        |
| ------------ | ------------------------------------- | -------------- |
| Polling      | `setInterval(POLL_INTERVAL_MS)`       | 30 s (default) |
| Event-driven | WebSocket `Swap` listener on the pool | ~block time    |

Both paths call the same `checkAndRebalance()`. The event path deduplicates by block number so multiple swaps in one block produce a single rebalance check.

---

### Frontend

A Next.js 15 app (`frontend/`) built with Wagmi v2 + RainbowKit + Tailwind CSS.

```
frontend/src/
├── app/page.tsx              ← 3-column layout (stats · deposit · history)
├── components/
│   ├── VaultStats.tsx        ← TVL, APY, share price, rebalance count
│   ├── DepositWithdraw.tsx   ← deposit/withdraw form with approval flow
│   ├── UserPosition.tsx      ← user share balance and underlying token value
│   ├── PriceRangeCard.tsx    ← visual tick range vs. current price
│   ├── RebalanceHistory.tsx  ← event log with timestamps and tx links
│   └── Header.tsx            ← wallet connect, network toggle
├── hooks/
│   ├── useVault.ts           ← vault/pool/user/metrics data (wagmi reads)
│   ├── useVaultActions.ts    ← deposit/withdraw tx flow with approval state
│   └── useVaultPage.ts       ← aggregates all hooks; computes APY
└── lib/
    ├── contracts.ts          ← ABI + vault address (from env)
    ├── wagmi.ts              ← RainbowKit + Wagmi config
    └── utils.ts              ← decimal formatting helpers
```

Key data refresh intervals: vault state 10 s · pool state 5 s · user position 5 s · metrics 15 s.

The test suite covers:

- **Unit**: constructor, deposit, depositToken1, withdraw, redeem, position management, admin functions, view functions, edge cases
- **Integration**: multi-user flows, multi-rebalance sequences, fee deduction verification
- **Invariant**: stateful campaigns verifying `totalAssets ≥ totalSupply × sharePrice` and share/token accounting invariants
- **Fuzz**: random input generation for all core functions
- **Fork**: behaviour against real Mezo Testnet contracts

## Maintenance Commitment

This project is submitted for the Mezo DEX Automated LP Rebalancing Vault bounty. I commit to maintaining, bug-fixing, and upgrading the vault for **at least 6 months post-mainnet deployment** under the following support model:

- **Critical / high security findings**: patched within 48 hours; new deployment if required
- **Bug fixes**: addressed within 1 week of confirmed report
- **Dependency upgrades**: Foundry, OpenZeppelin, and Node.js deps reviewed monthly
- **Feature requests**: evaluated on a best-effort basis; community input welcomed via GitHub Issues
- **Incident response**: vault `setPaused(true)` will be exercised immediately if an exploit is suspected; users notified within 1 hour
- **Communication**: status updates posted to the GitHub repository and, where applicable, the Mezo community channels

## Contributing

Bug reports, security disclosures, and pull requests are welcome.

- Open an [issue](../../issues) to report bugs or request features
- For security vulnerabilities, please disclose privately before opening a public issue
- PRs should include tests covering any new behaviour
- Run `forge test` and `forge fmt` before submitting

## License

[MIT](LICENSE) © 2025 MananSinghal123
