# Invariant Map

> Mezo Rebalancer Vault | 22 guards | 14 inferred | 5 not enforced on-chain

---

## 1. Enforced Guards (Reference)

Per-call preconditions. Heading IDs below (`G-N`) are anchor targets from x-ray.md attack surfaces.

#### G-1
`if (msg.sender != _s().owner) revert NotOwner()` · `RebalancerVaultUpgradeable.sol:141` · Gates all admin config setters to the single owner key.

#### G-2
`if (msg.sender != _s().operator) revert NotOperator()` · `RebalancerVaultUpgradeable.sol:146` · Restricts `rebalance` / `collectFees` to the keeper.

#### G-3
`if (_s().paused) revert Paused()` · `RebalancerVaultUpgradeable.sol:151` · Freezes deposits/withdrawals/rebalance when paused.

#### G-4
`if (_s().tokenId == 0) revert NotInitialized()` · `RebalancerVaultUpgradeable.sol:156` · Blocks fee-collect/rebalance before a position exists.

#### G-5
`if (assets > maxDeposit(receiver)) revert ExceedsMaxDeposit()` · `RebalancerVaultUpgradeable.sol:384` · Blocks deposits when spot deviates from TWAP or vault paused.

#### G-6
`if (assets <= DEAD_SHARES) revert BelowMinDeposit()` · `RebalancerVaultUpgradeable.sol:396` · First deposit must exceed the 1000 dead-share floor (inflation-attack guard).

#### G-7
`if (shares == 0) revert ZeroAmount()` · `RebalancerVaultUpgradeable.sol:409` · Rejects deposits that round to zero shares.

#### G-8
`if (block.number <= s.lastDepositBlock[owner_]) revert SameBlock()` · `RebalancerVaultUpgradeable.sol:450` · Prevents same-block deposit→withdraw (flash-loan share arbitrage).

#### G-9
`if (block.number <= s.lastDepositBlock[owner_]) revert SameBlock()` · `RebalancerVaultUpgradeable.sol:501` · Same-block guard on redeem path.

#### G-10
`if (finalIdle0 < assets) revert InsufficientToken0ForWithdraw(...)` · `RebalancerVaultUpgradeable.sol:487` · Ensures the exact requested token0 is available after unwind+swap.

#### G-11
`if (s.tokenId != 0) revert AlreadyInitialized()` · `RebalancerVaultUpgradeable.sol:643` · One-shot latch on first position mint.

#### G-12
`if (tickLower >= tickUpper) revert InvalidRange()` · `RebalancerVaultUpgradeable.sol:644` · Rejects degenerate initial ranges.

#### G-13
`if (newLiquidity == 0) revert NoLiquidityMinted()` · `RebalancerVaultUpgradeable.sol:663,866` · Ensures mint produced real liquidity.

#### G-14
`if (bps > 1000) revert FeeTooHigh()` · `RebalancerVaultUpgradeable.sol:931` · Caps performance fee proposal at 10%.

#### G-15
`if (block.timestamp < s.feeChangeActiveAt) revert TimelockActive()` · `RebalancerVaultUpgradeable.sol:942` · Enforces 2-day timelock before a fee change activates.

#### G-16
`if (token == s.token0 || token == s.token1) revert InvalidToken()` · `RebalancerVaultUpgradeable.sol:950` · Prevents owner sweeping the vault's core assets.

#### G-17
`if (seconds_ < 60) revert TwapTooShort()` · `RebalancerVaultUpgradeable.sol:959` · Floors TWAP window at 60s to limit manipulability.

#### G-18
`if (ticks <= 0 || ticks > 1000) revert DeviationOutOfRange()` · `RebalancerVaultUpgradeable.sol:964` · Bounds spot-vs-TWAP deviation tolerance.

#### G-19
`if (bps > 500) revert SlippageTooHigh()` · `RebalancerVaultUpgradeable.sol:969` · Caps swap/mint slippage tolerance at 5%.

#### G-20
`if (lo >= hi) revert InvalidRange(); if (lo < MIN_TICK || hi > MAX_TICK) revert InvalidStrategyTicks()` · `RebalancerVaultUpgradeable.sol:1288-1290` · Re-validates untrusted strategy output before minting.

#### G-21
`if (deviation > maxTwapDeviationTicks) revert PriceDeviatedFromTwap()` · `OracleLib.sol:47` · Core spot-near-TWAP gate reused across all value-moving flows.

#### G-22
`if (msg.sender != s.pendingOwner) revert NotPendingOwner()` · `RebalancerVaultUpgradeable.sol:885` · Two-step ownership acceptance guard.

---

## 2. Inferred Invariants (Single-Contract)

#### I-1

`Conservation` · On-chain: **Yes**

> Collected fees split exactly: `net0 + fee0 == tokensOwed0` and `Δ(totalFees0Earned) == fee0` (likewise token1).

**Derivation** — Δ-pair: `RebalancerVaultUpgradeable.sol:718` (`net0 = tokensOwed0 - fee0`) ↔ `:721` (`s.totalFees0Earned += fee0`); fee computed in `_deductPerformanceFee:1150`.

**If violated** — Fee accounting drifts from actual collected amounts.

---

#### I-2

`Bound` · On-chain: **Yes**

> `performanceFeeBps ∈ [0, 1000]` (≤10%) at all times.

**Derivation** — guard-lift: `require(bps <= 1000)` at `proposePerformanceFee:931`. Write sites: `initialize:186` (=1000), `applyPerformanceFee:943` (= pendingFeeBps, itself bounded by the propose guard). All writers respect the bound.

**If violated** — Excess fee extraction from yield.

---

#### I-3

`Bound` · On-chain: **Yes**

> `slippageBps ∈ [0, 500]` (≤5%).

**Derivation** — guard-lift: `require(bps <= 500)` at `setSlippageBps:969`. Write sites: `initialize:189` (=50), `setSlippageBps:970`. Both bounded.

**If violated** — Swaps/mints accept unbounded slippage.

---

#### I-4

`Bound` · On-chain: **Yes**

> `twapSeconds >= 60`.

**Derivation** — guard-lift: `require(seconds_ >= 60)` at `setTwapSeconds:959`. Write sites: `initialize:187` (=300), `setTwapSeconds:960`. Both bounded.

**If violated** — Short TWAP window becomes cheaply manipulable.

---

#### I-5

`Bound` · On-chain: **Yes**

> `maxTwapDeviationTicks ∈ (0, 1000]`.

**Derivation** — guard-lift: `require(ticks > 0 && ticks <= 1000)` at `setMaxTwapDeviationTicks:964`. Write sites: `initialize:188` (=200), `setMaxTwapDeviationTicks:965`.

**If violated** — Deviation gate could be disabled (0) or made meaningless (huge).

---

#### I-6

`StateMachine` · On-chain: **Yes**

> `tokenId` transitions `0 → nonzero` exactly once via `initializePosition`; thereafter only `rebalance` may replace it with a freshly minted id (never back to 0).

**Derivation** — edge: `tokenId==0`@643 → `s.tokenId = newTokenId`@664. Reverse blocked by `AlreadyInitialized` guard (G-11).

**If violated** — Re-initialization could orphan the live NFT position.

---

#### I-7

`StateMachine` · On-chain: **Yes**

> Ownership is two-step: `pendingOwner` set by current owner, then latched to `owner` only by the pending address, resetting `pendingOwner` to 0.

**Derivation** — edge: `transferOwnership:879` sets `pendingOwner`; `acceptOwnership:885-888` requires `msg.sender == pendingOwner`, sets `owner`, clears `pendingOwner`.

**If violated** — Ownership could transfer to an address that never accepted (typo bricking).

---

#### I-8

`Temporal` · On-chain: **Yes**

> A proposed fee change cannot apply before `feeChangeActiveAt = proposeTime + 2 days`.

**Derivation** — temporal: `s.feeChangeActiveAt = block.timestamp + 2 days` (`:936`) checked by `require(block.timestamp >= feeChangeActiveAt)` (`applyPerformanceFee:942`).

**If violated** — Fee changes bypass the user-exit window.

---

#### I-9

`Temporal` · On-chain: **Yes**

> A holder cannot withdraw/redeem in the same block they deposited: `withdraw/redeem` require `block.number > lastDepositBlock[owner]`.

**Derivation** — temporal: `s.lastDepositBlock[receiver] = block.number` (`:388,425,598`) checked at `:450,501`.

**If violated** — Enables single-block deposit→price-move→withdraw share arbitrage.

---

#### I-10

`Conservation` · On-chain: **Yes**

> On the first deposit, `DEAD_SHARES` (1000) are minted to `0xdead` and permanently subtracted from the depositor's shares.

**Derivation** — Δ-pair: `_mint(0xdead, DEAD_SHARES)`@397 with `shares = assets - DEAD_SHARES`@398 (mirrored in `mint:436`, `depositToken1:617`).

**If violated** — First-depositor inflation attack becomes viable.

---

#### I-11

`Ratio` · On-chain: **Yes**

> `convertToShares(assets) = assets · totalSupply / totalAssets` (floor); `convertToAssets(shares) = shares · totalAssets / totalSupply` (floor).

**Derivation** — `convertToShares:303` / `convertToAssets:313`, both `Math.mulDiv` of two storage-derived quantities (`totalSupply()`, `totalAssets()`).

**If violated** — Share pricing diverges from backing value.

---

#### I-12

`Ratio` · On-chain: **No**

> `totalAssets()` = idle token0 + position principal + owed fees + (idle+position token1 valued at **TWAP**). Idle balances are read via `balanceOf(address(this))`, so a direct token transfer (donation) inflates it.

**Derivation** — `_totalVaultValueInToken0:1010-1047` reads `IERC20(token0).balanceOf(this)` and `IERC20(token1).balanceOf(this)`; no internal accounting counterpart. No guard enforces `accounted == balanceOf`.

**If violated** — Donation shifts share price; mitigated only by DEAD_SHARES (I-10), not eliminated.

---

#### I-13

`Bound` · On-chain: **No**

> Fee-owed subtraction assumes `tokensOwed >= principal`: `feesOwed0 = tokensOwed0 - uint128(principal0)`.

**Derivation** — guard-lift (negative): `RebalancerVaultUpgradeable.sol:802-803` performs unchecked-in-intent uint128 subtraction with no `require(tokensOwed0 >= principal0)`. No write site establishes the ordering invariant; it relies on position-manager return semantics.

**If violated** — Underflow reverts rebalance, or (if semantics differ) misattributes principal as fee.

---

#### I-14

`Temporal` · On-chain: **Yes**

> Every liquidity mint/decrease/collect/swap carries `deadline = block.timestamp + 300`.

**Derivation** — temporal: `deadline: block.timestamp + 300` at `:659,690,787,862,1104,1134`.

**If violated** — Stale queued txs could execute at unfavorable later prices.

---

**Categories:**
- **Conservation**: equal-and-opposite deltas in one function body.
- **Bound**: a storage variable constrained across all write sites.
- **Ratio**: a value defined as a formula of other storage variables.
- **StateMachine**: discrete transitions guarded against reversal.
- **Temporal**: a condition on `block.timestamp` / `block.number` / a deadline.

---

## 3. Inferred Invariants (Cross-Contract)

#### X-1

On-chain: **No**

> Vault valuation trusts `OracleLib.getTwapSqrtPrice` to reflect fair token1/token0 price; `totalAssets()` is priced purely from TWAP with no spot cross-check in the view path.

**Caller side** — `RebalancerVaultUpgradeable.sol:1044` (`token1ToToken0(bal1, getTwapSqrtPrice(...))`) feeds `convertToShares/Assets`.

**Callee side** — `OracleLib.sol:19-22` derives the TWAP tick solely from `ICLPool.observe`; a pool with a short/thin observation history or attacker-seeded observations moves it.

**If violated** — Mispriced shares on deposit/redeem. Value-moving flows add `requireSpotNearTwap` (G-21), but `totalAssets()`/`maxWithdraw` reads do not.

---

#### X-2

On-chain: **No**

> The vault delegatecalls `dexAdapter` code into its own storage/token context, trusting it fully; `setDexAdapter` and `setStrategy` can repoint these to arbitrary code.

**Caller side** — `_delegateAdapter:1218` executes `dexAdapter.delegatecall(data)` with vault funds/NFT in scope.

**Callee side** — `setDexAdapter:921-924` / `setStrategy:915-918` write the target with only a zero-address check.

**If violated** — A malicious adapter/strategy set by owner can move all vault funds (owner trust boundary).

---

#### X-3

On-chain: **Yes**

> Vault re-validates the untrusted strategy's tick output before use.

**Caller side** — `_strategyRange:1284` calls `IStrategy.computeRange`, then asserts `lo < hi` and TickMath bounds (`:1288-1290`).

**Callee side** — `Strategy.sol:18-24` computes ticks from TWAP; output cannot bypass the caller-side check.

**If violated** — N/A while re-validation stays; removing it would let a bad strategy force invalid ranges.

---

## 4. Economic Invariants

#### E-1

On-chain: **No**

> Share price should rise only from accrued swap fees, never from manipulation or donation.

**Follows from** — I-11 (ratio) + I-12 (balanceOf-based totalAssets) + X-1 (TWAP valuation).

**If violated** — A donation or TWAP shift changes redemption value for existing holders; DEAD_SHARES (I-10) blunts but does not remove the first-depositor case.

---

#### E-2

On-chain: **No**

> Net asset value out on redeem should not exceed pro-rata backing.

**Follows from** — I-1 (fee split) + I-11 (ratio) + X-1 (TWAP price used to value the token1 leg paid out in `redeem`).

**If violated** — Redeemers valued at a TWAP that diverges from executable price could extract more/less than fair share; the token1 leg is paid in kind, so realized value depends on the same TWAP.
