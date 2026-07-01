# X-Ray Report

> Mezo Rebalancer Vault | 2342 nSLOC | 440af78ed (`main`) | Foundry | 01/07/26

Analyzed branch: `main` at `440af78ed`.

---

## 1. Protocol Overview

**What it does:** An ERC-4626 vault that holds a single concentrated-liquidity (Uniswap-V3-style) position on a pool and lets a keeper rebalance the range around the TWAP tick, auto-compounding swap fees for share holders.

- **Users**: LPs deposit token0 (or token1) and receive vault shares; redeem for the pro-rata underlying.
- **Core flow**: `deposit` → keeper `rebalance` centers the CL range on TWAP and swaps to the target ratio → `withdraw/redeem` unwinds the position.
- **Key mechanism**: Single active CL NFT position; range = `[floor(twap-halfWidth), ceil(twap+halfWidth)]`; all pricing/valuation via pool TWAP, spot only gated against TWAP.
- **Token model**: `token0` = ERC-4626 asset; `token1` = pool counter-asset; shares are the vault ERC-20. 1000 `DEAD_SHARES` burned to `0xdead` on first deposit.
- **Admin model**: Per-vault `owner` (config + upgrades via beacon), `operator` (rebalance/collect), `guardian` (pause; set to the Factory). Factory owner deploys vaults and controls the shared beacon implementation.

For a visual overview of the protocol's architecture, see the [architecture diagram](architecture.svg).

### Contracts in Scope

| Subsystem | Key Contracts | nSLOC | Role |
|-----------|--------------|------:|------|
| Vault core | RebalancerVaultUpgradeable | 1101 | ERC-4626 vault, deposits/withdraws, rebalance, admin, valuation |
| Factory | VaultFactory | 174 | Beacon + BeaconProxy deployer, guardian pause fan-out |
| DEX seam | CLDexAdapter | 136 | Stateless delegatecall/staticcall adapter to pool/position-manager/router |
| Math/oracle libs | VaultMath, OracleLib, VaultStorageLib | 234 | TWAP, tick math, slippage, ERC-7201 storage |
| Strategy | Strategy | 27 | Stateless range + optimal-swap module (re-validated by vault) |
| View | VaultLens | 150 | Off-chain read helper (share price, position, rebalance params) |

### How It Fits Together

The core trick: the vault never trusts spot price for value — everything is priced from the pool TWAP, and spot is only allowed to *transact* when it sits within `maxTwapDeviationTicks` of that TWAP.

### Deposit

```
Vault.deposit(assets, receiver)
├─ _requireSpotNearTwap()          — reverts if spot deviates from TWAP (G-21)
├─ lastDepositBlock[receiver]=block.number   — same-block withdraw guard
├─ IERC20(token0).safeTransferFrom(sender → vault)
└─ _mint(receiver, shares)         — first deposit burns 1000 DEAD_SHARES to 0xdead
```
*Funds sit idle until a rebalance folds them into the position.*

### Rebalance (operator)

```
Vault.rebalance(swapZeroForOne, swapAmount)
├─ _requireSpotNearTwap()
├─ _rebalanceRemoveFeeCollectBurn()
│   ├─ CLDexAdapter.decreaseLiquidity() [delegatecall]   — pulls principal
│   ├─ feesOwed = tokensOwed - principal                  — uint128 subtraction (I-13)
│   ├─ _deductPerformanceFee() → safeTransfer to feeRecipient
│   ├─ CLDexAdapter.collect() [delegatecall]
│   └─ CLDexAdapter.burn() [delegatecall]
├─ _executeSwap()                   — minOut from TWAP·slippageBps
└─ _rebalanceMintNew()
    ├─ IStrategy.computeRange(twapTick, spacing) → re-validated (G-20)
    └─ CLDexAdapter.mint() [delegatecall]   — new NFT, tokenId updated
```
*Writes execute in the vault's context via `delegatecall`, so tokens/NFT/approvals stay in the vault.*

### Redeem

```
Vault.redeem(shares, receiver, owner_)
├─ same-block guard, _requireSpotNearTwap()
├─ _removeProportionalLiquidity()   — decreaseLiquidity(pro-rata) + collect(ALL fees)
├─ separate principal (p0/p1) from swept fees, credit redeemer only pro-rata fee share
├─ _burn(owner_, shares)
└─ safeTransfer token0 + token1 to receiver   — paid in kind, both legs
```
*`assets` return value converts the token1 leg at TWAP; the payout itself is in-kind.*

### Factory deploy + seed

```
VaultFactory.deploySeedAndInitialize()
├─ _deploy() → new BeaconProxy(beacon, initData)   — initialize() runs in ctor
├─ safeTransferFrom(seeder → factory) → deposit(seed)
├─ v.initializePosition(...)        — mints first CL position
└─ v.transferOwnership(realOwner)   — factory hands off (two-step: pending)
```

---

## 2. Threat & Trust Model

### Protocol Threat Profile

> Protocol classified as: **Yield Aggregator / Vault (ERC-4626)** with **DEX/AMM (concentrated-liquidity manager)** characteristics

Signals: `deposit`/`withdraw`/`convertToShares`/`totalAssets` (ERC-4626) plus a single managed CL position, `sqrtPriceX96`/`tick`/TWAP observation and `exactInputSingle` swaps (AMM). It is an automated liquidity manager: user-facing vault accounting on top of an AMM position, so first-depositor inflation, donation/valuation, TWAP manipulation, and keeper/admin trust dominate.

### Actors & Adversary Model

| Actor | Trust Level | Capabilities |
|-------|-------------|-------------|
| Owner (per vault) | Trusted | Instant: `setStrategy`, `setDexAdapter` (repoint delegatecall target — full fund control), `setOperator`, `setGuardian`, `setPaused`, `sweepToken` (non-core only), all TWAP/slippage params, `initializePosition`. Fee changes 2-day timelocked. No timelock on the rest. |
| Factory Owner | Trusted | Deploys vaults; controls the shared **beacon implementation** (`upgradeTo`) — instant upgrade of every vault. |
| Operator | Bounded (rebalance/collect only, gated by spot-near-TWAP + on-chain slippage floors) | `rebalance`, `collectFees`. Cannot set min amounts freely (computed on-chain). Subject to `whenNotPaused`. |
| Guardian (= Factory) | Bounded (pause only) | `pauseByGuardian` / `pauseAll`. Cannot unpause (owner-only) or move funds. |
| Depositor / share owner | Untrusted | `deposit`/`mint`/`depositToken1`/`withdraw`/`redeem`. Same-block deposit→withdraw blocked. |

**Adversary Ranking:**

1. **Malicious first depositor / donation attacker** — Manipulates share price on the empty vault or via direct token transfer into `totalAssets`'s `balanceOf` reads.
2. **TWAP manipulator** — All valuation and swap floors derive from pool TWAP; a thin/short-history pool or seeded observations shift it.
3. **Compromised/careless Owner** — `setDexAdapter`/`setStrategy` and the beacon upgrade are instant, full-fund-control levers.
4. **MEV / sandwich searcher** — Targets the keeper's `rebalance` swap and the `withdraw` shortfall swap.
5. **Malicious keeper (Operator)** — Bounded by on-chain slippage floors, but chooses rebalance timing and swap direction/amount.

See [entry-points.md](entry-points.md) for the full permissionless entry point map.

### Trust Boundaries

- **Owner → vault funds** — `setDexAdapter:921` / `setStrategy:915` repoint a `delegatecall` target executed with vault funds/NFT in scope; only a zero-address check, no timelock. Worst instant action: point adapter at draining code. *Git signal: access_control touched in 7 commits.*
- **Factory beacon → all vaults** — `UpgradeableBeacon.upgradeTo` (factory owner) instantly swaps the implementation for every deployed vault; single key, no timelock.
- **Vault → CLDexAdapter (delegatecall)** — adapter is stateless but runs in vault context; correctness of approvals/refunds is fully delegated (X-2).
- **Vault → pool TWAP** — the sole price source for valuation and slippage floors; `twapSeconds ≥ 60` and deviation gate are the only defenses (X-1).
- **Guardian seat** — pause is fanned out from the Factory; owner alone can unpause, so a stuck guardian cannot trap funds beyond a pause.

### Key Attack Surfaces

- **Owner-set delegatecall/strategy targets** &nbsp;&#91;[X-2](invariants.md#x-2)&#93; — `setDexAdapter:921` / `setStrategy:915` change code run against vault funds with no timelock; worth confirming the intended owner is a multisig/timelock and that adapter code is immutable in practice.

- **`totalAssets` uses `balanceOf(this)` for idle legs** &nbsp;&#91;[I-12](invariants.md#i-12), [E-1](invariants.md#e-1)&#93; — `_totalVaultValueInToken0:1010-1047` reads raw balances; worth tracing whether a direct token transfer (donation) between deposits shifts share price beyond the DEAD_SHARES cushion.

- **All valuation priced at TWAP only** &nbsp;&#91;[X-1](invariants.md#x-1)&#93; — `totalAssets`/`convertTo*`/`maxWithdraw` read TWAP with no spot cross-check in the view path (spot gate is only on the mutating call); worth checking behavior on low-liquidity pools or short observation cardinality.

- **Fee-vs-principal uint128 subtraction** &nbsp;&#91;[I-13](invariants.md#i-13)&#93; — `_rebalanceRemoveFeeCollectBurn:802-803` computes `tokensOwed - principal` with no `>=` check; worth confirming position-manager return semantics guarantee `tokensOwed ≥ principal` in all paths.

- **`redeem` in-kind token1 leg valued at TWAP** &nbsp;&#91;[E-2](invariants.md#e-2), [X-1](invariants.md#x-1)&#93; — `redeem:558-563` pays token1 directly and reports `assets` via TWAP; worth tracing the fee-vs-principal separation math (`swept0 - p0`) for rounding/under-provision edges.

- **Beacon upgrade blast radius** — one `upgradeTo` on the Factory reconfigures every vault's logic instantly; worth confirming upgrade authority and storage-layout discipline (ERC-7201 namespaced storage is used).

- **Keeper rebalance swap MEV** &nbsp;&#91;[I-3](invariants.md#i-3)&#93; — swap `minOut` is TWAP·(1-slippageBps) with slippageBps ≤500; worth checking that the TWAP-derived floor is tight enough on volatile pairs to prevent sandwich extraction.

### Upgrade Architecture Concerns

- **Beacon proxy, shared implementation** — `VaultFactory is UpgradeableBeacon`; every vault is a `BeaconProxy` pointing at one implementation, so an upgrade is all-or-nothing across vaults (`VaultFactory.sol:18,194`).
- **Namespaced storage** — `VaultStorageLib` uses an ERC-7201 slot (`mezo.storage.RebalancerVault`), reducing collision risk on upgrade; worth verifying no future field reordering within the struct.
- **Implementation initializer disabled** — constructor calls `_disableInitializers()` (`:161`); `initialize` is `initializer`-gated and only reachable via the proxy constructor.

### Protocol-Type Concerns

**As a Yield Vault (ERC-4626):**
- Share rounding uses `Floor` on deposit/convert (`:303,313`) and `Ceil` on `previewMint`/`previewWithdraw` (`:347,365`); worth confirming direction always favors the vault, especially the `redeem` fee-separation math (`:532-535`).
- `totalAssets` includes owed fees valued at TWAP; a harvest-sandwich around `rebalance`/`collectFees` is worth checking since fees fold into share value.

**As a CL Manager (AMM):**
- `VaultMath.token0ToToken1`/`token1ToToken0` use `mulDiv` on `sqrtPriceX96²` (`:22-43`); worth checking precision/overflow at extreme ticks and for low-decimal tokens (`decimals0/1` read via a `staticcall` that falls back to 18).
- `computeOptimalSwap` (`VaultMath.sol:45-92`) drives the keeper's swap size; worth checking the in-range value-ratio math for the one-token-balance edge cases it explicitly claims to handle.

### Temporal Risk Profile

**Deployment & Initialization:**
- First-deposit empty-state handled by DEAD_SHARES (`:396`), but `initializePosition` is a separate owner tx — worth confirming the deploy→seed→init sequence (or `deploySeedAndInitialize`) is always used so no vault sits initialized-but-unseeded with a live share price.
- `initialize` front-running is mitigated: it runs inside the `BeaconProxy` constructor with factory-encoded params (`VaultFactory.sol:175-194`).

**Market Stress:**
- Under volatility the spot-near-TWAP gate (G-21) blocks deposits/withdraws/rebalance entirely — worth confirming this fail-closed behavior is acceptable (funds locked until spot reconverges) rather than a griefing lever.

---

### Composability & Dependency Risks

**Dependency Risk Map:**

> **CL Pool (TWAP + slot0)** — via `OracleLib` / `CLDexAdapter.slot0`/`observe`
> - Assumes: `observe` returns a well-populated observation array; TWAP reflects fair price
> - Validates: spot-vs-TWAP deviation (G-21); `twapSeconds ≥ 60`; but no observation-cardinality / zero check
> - Mutability: external pool, immutable per vault (set at init)
> - On failure: reverts (fail-closed) if `observe` reverts or price deviates

> **NonfungiblePositionManager** — via `CLDexAdapter` (delegatecall)
> - Assumes: standard mint/decrease/collect/burn semantics; `tokensOwed ≥ principal` after decrease
> - Validates: amount0Min/amount1Min slippage floors; `newLiquidity != 0`
> - Mutability: external, fixed per vault
> - On failure: reverts and bubbles up (assembly revert in `_delegateAdapter:1219`)

> **SwapRouter** — via `CLDexAdapter.exactInputSingle` (delegatecall)
> - Assumes: honors `amountOutMinimum`; pulls exactly `amountIn`
> - Validates: `amountOutMinimum` = TWAP-derived floor (I-3)
> - Mutability: external, fixed per vault
> - On failure: reverts

**Token Assumptions** *(unvalidated only)*:
- Fee-on-transfer token0/token1: `deposit` credits shares against `assets` (the requested amount), not the delta actually received — impact: over-crediting shares if a fee token is used.
- Rebasing token0/token1: `totalAssets` reads `balanceOf` live, so positive rebases silently accrue to holders and negative rebases understate backing — impact: accounting drift.
- Decimals: read once via `staticcall` with a fallback to 18 (`_safeDecimals:1168`) — impact if a token mis-reports: valuation scaling error.

**Shared State Exposure:**
- The vault both trades on and reads TWAP from the *same* pool; large `rebalance`/`withdraw` swaps move the pool the vault prices against, coupling execution and valuation within nearby blocks.

---

## 3. Invariants

> ### 📋 Full invariant map: **[invariants.md](invariants.md)**
>
> A dedicated reference file contains the complete invariant analysis — do not look here for the catalog.
>
> - **22 Enforced Guards** (`G-1` … `G-22`) — per-call preconditions with Check / Location / Purpose
> - **14 Single-Contract Invariants** (`I-1` … `I-14`) — Conservation, Bound, Ratio, StateMachine, Temporal
> - **3 Cross-Contract Invariants** (`X-1` … `X-3`) — TWAP valuation, delegatecall trust, strategy re-validation
> - **2 Economic Invariants** (`E-1` … `E-2`) — share-price integrity, redeem fairness
>
> Every inferred block cites a concrete Δ-pair, guard-lift + write-sites, state edge, or temporal predicate. The **On-chain=No** blocks (I-12, I-13, X-1, X-2, E-1, E-2) are the high-signal ones. Attack-surface bullets above cross-link directly into the relevant blocks.

---

## 4. Documentation Quality

| Aspect | Status | Notes |
|--------|--------|-------|
| README | Present | `README.md` (16 KB, protocol-level) |
| NatSpec | ~21 annotations | Good on interfaces (IStrategy) and key mechanics (redeem fee separation, delegatecall seam); sparse on setters |
| Spec/Whitepaper | Missing | No dedicated design doc; `docs/` present but not a formal spec |
| Inline Comments | Adequate | Strong where it matters (valuation, swap-ratio math, delegatecall rationale) |

---

## 5. Test Analysis

| Metric | Value | Source |
|--------|-------|--------|
| Test files | 25 | File scan (always reliable) |
| Test functions | 146 | File scan (always reliable) |
| Line coverage | Unavailable — 17 of 146 tests fail (fork/balance-setup errors), coverage aborts | Coverage tool (requires passing compile+run) |
| Branch coverage | Unavailable — same reason | Coverage tool |

25 test files with 146 test functions detected; coverage metrics unavailable because 17 tests currently fail (fork setup `AlreadyInitialized`, `ERC20InsufficientBalance` in position/lifecycle tests, and one `computeMintSlippage` arithmetic underflow). Test *existence* is confirmed by file scan and is independent of these runtime failures.

### Test Depth

| Category | Count | Contracts Covered |
|----------|-------|-------------------|
| Unit | ~140 | Vault, Factory, VaultMath, BeaconProxy, Position lifecycle |
| Fork | 1 | InitializePosition (currently failing) |
| Stateless Fuzz | 0 | none |
| Stateful Fuzz (Foundry) | 0 | none — invariant profile configured in foundry.toml but no `invariant_` tests found |
| Stateful Fuzz (Echidna) | 0 | none |
| Stateful Fuzz (Medusa) | 0 | none |
| Formal Verification (Certora) | 0 | none |
| Formal Verification (Halmos) | 0 | none |

### Gaps

- **No stateful/invariant fuzzing** despite a configured `[profile.default.invariant]` campaign in `foundry.toml` — highest-priority gap for a share-accounting + AMM-math vault. The declared invariants (I-1, I-10, I-11, X-3) are prime fuzz targets.
- **No stateless fuzz** on `VaultMath` (`token0ToToken1`, `computeOptimalSwap`, `computeMintSlippage`) — math is the core risk and one unit test already trips an underflow.
- **No formal verification** of the ERC-4626 round-trip properties (I-11) or fee conservation (I-1).
- **17 failing tests** including the only fork test — the live-fork valuation/rebalance path is not currently green.

---

## 6. Developer & Git History

> Repo shape: normal_dev — 19 of 39 commits touch source over 55 days (2026-05-05 → 2026-06-29); single developer.

### Contributors

| Author | Commits | Source Lines (+/-) | % of Source Changes |
|--------|--------:|--------------------|--------------------:|
| MananSinghal123 | 39 | +6498 / -3331 | 100% |

### Review & Process Signals

| Signal | Value | Assessment |
|--------|-------|------------|
| Unique contributors | 1 | Single-dev |
| Merge commits | 0 of 39 (0%) | No merge commits — no peer-review signal |
| Repo age | 2026-05-05 → 2026-06-29 | ~55 days |
| Recent source activity (30d) | Multiple (last: 2026-06-29) | Active; mostly UI/frontend chores late |
| Test co-change rate | 78.9% | % of source commits also touching tests (co-modification, not coverage) |

### File Hotspots

| File | Modifications | Note |
|------|-------------:|------|
| RebalancerVaultUpgradeable.sol | 7 | Core vault — highest-priority review |
| RebalancerVault.sol (removed) | 7 | Predecessor monolith, replaced by upgradeable version |
| CLDexAdapter.sol | 5 | Delegatecall seam churn |
| VaultMath.sol | 4 | Core math |
| OracleLib.sol | 3 | TWAP logic |

### Security-Relevant Commits

| SHA | Date | Subject | Score | Key Signal |
|-----|------|---------|------:|------------|
| f38c45374 | 2026-05-29 | fix: frontend build errors | 19 | adds runtime guards, tightens access control, touches transfer/accounting |
| c7b5afeb6 | 2026-06-03 | update: beacon proxy pattern | 14 | removes guards (+3/-51), loosens access control, spans 5 security domains |
| 4934a4445 | 2026-06-01 | fix: _s() routing, double-slot0, fee isolation | large | 3145-line refactor, no test changes |

### Dangerous Area Evolution

| Security Area | Commits | Key Files |
|--------------|--------:|-----------|
| oracle_price | 15 | RebalancerVaultUpgradeable, OracleLib, VaultMath |
| fund_flows | 10 | RebalancerVaultUpgradeable, CLDexAdapter, VaultFactory |
| access_control | 7 | RebalancerVaultUpgradeable, VaultFactory |

### Forked Dependencies

| Library | Path | Upstream | Status | Notes |
|---------|------|----------|--------|-------|
| openzeppelin-contracts | lib/openzeppelin-contracts | OpenZeppelin | Submodule | Standard, not internalized |
| openzeppelin-contracts-upgradeable | lib/openzeppelin-contracts-upgradeable | OpenZeppelin | Submodule | Standard |
| v3-core / v3-periphery | lib/v3-core | Uniswap V3 | Submodule (`git status`: dirty) | `lib/v3-core` shows local modifications — worth confirming no divergence from upstream TickMath/LiquidityAmounts |

### Technical Debt Markers

None detected (0 TODO/FIXME/HACK in source).

### Security Observations

- **Single-developer, zero merge commits** — 100% of source by MananSinghal123; no peer-review signal in history.
- **`beacon proxy pattern` commit removed 51 guard lines and loosened access control across 5 domains** — c7b5afeb6 warrants a manual before/after diff.
- **3145-line refactor (4934a4445) shipped with no test changes** — largest single diff, touches oracle+fund-flow paths.
- **Fix-without-test rate 30%** — some fix-scored commits didn't co-modify tests (measures co-modification, not coverage).
- **`lib/v3-core` is dirty in the working tree** — local edits to a vendored math library are hidden attack surface if TickMath/LiquidityAmounts were altered.
- **oracle_price is the #1 churned area (15 commits)** — aligns with TWAP being the sole valuation source.

### Cross-Reference Synthesis

- **RebalancerVaultUpgradeable is #1 in churn AND concentrates every top attack surface** → highest-leverage review: `_totalVaultValueInToken0`, `redeem` fee separation, `_rebalanceRemoveFeeCollectBurn`, adapter/strategy setters.
- **oracle_price churn (15) + TWAP-only valuation (X-1)** → the price path is both the most-modified and the most-trusted; deserves focused review of `OracleLib` + `VaultMath` conversions.
- **`beacon proxy` guard removal (c7b5afeb6) + 0 merge commits** → the migration that loosened access control had no second reviewer.

---

## X-Ray Verdict

**FRAGILE** — Unit tests exist broadly but 17 fail (incl. the only fork test), there is no fuzz/invariant/formal coverage despite math-heavy accounting, and single-key owner controls (delegatecall retargeting, beacon upgrade) have no timelock.

**Structural facts:**
1. 2342 nSLOC across 6 subsystems; one 1101-nSLOC core vault holds all fund logic.
2. Upgradeable via a shared beacon — one implementation backs every `BeaconProxy` vault.
3. 25 test files / 146 test functions exist; 17 currently fail; 0 fuzz, 0 invariant, 0 formal-verification tests.
4. 100% single-developer authorship, 0 merge commits over 55 days.
5. Fee changes are 2-day timelocked; `setDexAdapter`/`setStrategy`/beacon `upgradeTo` are instant single-key actions.
