# RebalancerVault — Test Suite

## Structure

```
test/
├── BaseTest.sol                        # Shared setup: mocks, actors, helpers
├── mocks/
│   ├── MockERC20.sol                   # Mintable ERC20 (8 or 18 decimals)
│   ├── MockCLPool.sol                  # Configurable slot0 / tickSpacing
│   ├── MockPositionManager.sol         # Full NFT PM simulation
│   └── MockCLSwapRouter.sol            # Configurable swap output / revert
├── unit/
│   ├── DepositWithdrawTest.t.sol       # deposit, mint, withdraw, redeem
│   ├── AdminTest.t.sol                 # ownership, operator, fees, pause, sweep
│   └── RebalanceTest.t.sol             # rebalance, collectFees, tick math
├── fuzz/
│   └── FuzzTest.t.sol                  # Property-based tests (1000 runs each)
├── invariant/
│   └── InvariantTest.t.sol             # Stateful invariants via VaultHandler
├── integration/
│   └── IntegrationTest.t.sol           # End-to-end multi-step scenarios
└── edge/
    └── EdgeCaseTest.t.sol              # Inflation attack, overflow, gas limits
```

---

## Running Tests

```bash
# All tests
forge test -vv

# Unit only
forge test --match-path "test/unit/*" -vv

# Fuzz (1000 runs)
forge test --match-path "test/fuzz/*" -vv

# Invariant
forge test --match-path "test/invariant/*" -vv

# Integration
forge test --match-path "test/integration/*" -vv

# Edge cases
forge test --match-path "test/edge/*" -vv

# Gas report
forge test --gas-report

# CI profile (faster)
FOUNDRY_PROFILE=ci forge test

# Deep overnight run
FOUNDRY_PROFILE=deep forge test
```

---

## What Each Suite Covers

### Unit Tests

| File                | Coverage                                                                                |
| ------------------- | --------------------------------------------------------------------------------------- |
| DepositWithdrawTest | deposit/mint/withdraw/redeem happy paths, reverts, events, ERC-4626 preview consistency |
| AdminTest           | ownership 2-step transfer, operator, pause, fee timelock, sweep, initializePosition     |
| RebalanceTest       | rebalance steps, fee deduction, tick alignment, failed mocks, extreme volatility        |

### Fuzz Tests

- Deposit always mints nonzero shares for valid inputs
- Second depositor gets proportional shares
- Deposit never inflates (redeemable ≤ deposited)
- previewMint rounds up correctly
- Redeem never exceeds proportional assets
- convertToShares/convertToAssets round-trip no-gain property
- Performance fee never exceeds configured bps
- Floor/ceil tick math always aligns to spacing
- Share price stable across deposits

### Invariant Tests

- `totalAssets` always non-negative and sane
- `totalSupply > 0` → vault is solvent
- Dead shares (`address(0xdead)`) never redeemable
- Share price never goes negative
- `performanceFeeBps` never exceeds 1000 (10%)
- No free shares from round-trip conversions
- `tokenId` always a sane value

### Integration Tests

1. Full lifecycle: deposit → init position → collect fees → rebalance → redeem
2. Multiple rebalances with fee accumulation
3. Multi-user share price stability
4. Mixed token0 + token1 deposits
5. Extreme volatility (price crash 90% then recovery)
6. Pause → unpause flow
7. Fee timelock cannot be bypassed
8. Low liquidity pool resilience
9. Reentrancy protection verified
10. Ownership transfer mid-operation
11. isOutOfRange detection
12. ERC721Receiver selector

### Edge Case Tests

- **Inflation attack** — dead shares mechanism prevents share price manipulation
- **Dead shares boundary** — exactly DEAD_SHARES reverts, +1 succeeds
- **Tick boundaries** — negative tick floor/ceil alignment
- **Decimal mismatch** — BTC (8) / MUSD (18) scaling
- **Gas budgets** — deposit <300k, redeem <300k, rebalance <500k, collectFees <200k
- **Allowance enforcement** — redeem/withdraw without allowance reverts
- **Sweep protection** — cannot steal token0 or token1 via sweep
- **Overflow resistance** — max uint inputs don't overflow
- **ETH receive** — vault accepts native ETH

---

## Mock Architecture

### MockPositionManager

- Stores positions in a mapping, simulates real PM behaviour
- `setMintReturn(liquidity, amount0, amount1)` — control what mint returns
- `setPendingFees(tokenId, fee0, fee1)` — seed uncollected fees
- `setShouldRevert(mint, decrease, collect)` — simulate failures
- `setLiquidity(tokenId, liquidity)` — override position liquidity
- Tracks call counts: `mintCallCount`, `burnCallCount`, `collectCallCount`

### MockCLSwapRouter

- `setAmountOut(amount)` — control swap output
- `setShouldRevert(bool)` — simulate failed swap
- `setShouldReturnLessThanMin(bool)` — simulate slippage violation

### MockCLPool

- `setPrice(sqrtPriceX96, tick)` — simulate price moves for volatility tests
