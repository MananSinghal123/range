# Modular & Upgradeable RebalancerVault — Design

**Date:** 2026-05-31
**Type:** Structural refactor only. No economic, accounting, or security behavior changes.

## Goal

Refactor the monolithic `RebalancerVault.sol` (non-upgradeable OZ ERC4626, 1377 lines) into a
modular, beacon-upgradeable architecture. Every guard, constant, rounding direction, and TWAP
rule is preserved **byte-for-byte in intent**; only signatures change where a module boundary
or the strategy-per-vault model demands it (see "Accepted interface changes").

## Hard constraints (preserved exactly)

- token0-numeraire share accounting; `totalAssets()` values idle + position + uncollected fees
  via **TWAP** (never `slot0`).
- `DEAD_SHARES = 1_000` inflation protection; same-block deposit/withdraw guard
  (`lastDepositBlock`).
- `_requireSpotNearTwap()` on **every** write path: deposit, depositToken1, mint, withdraw,
  redeem, rebalance.
- On-chain slippage floors derived from TWAP + `slippageBps`; operator/keeper can never pass
  min amounts.
- New range anchored on the **TWAP tick**, not spot.
- Performance-fee 2-day timelock; two-step ownership; ReentrancyGuard on all external
  state-changing fns; isolation of earned fees from principal in `rebalance`.
- Unchanged numeric constants: widths 300/700/1200, `DEAD_SHARES` 1000, `performanceFeeBps`
  default 1000 (cap 1000), `twapSeconds` default 300 (min 60), `maxTwapDeviationTicks` default
  200 (cap 1000), `slippageBps` default 50 (cap 500), 2-day timelock, all `+ 300` deadlines,
  `10_000` bps base.
- No new deps except OpenZeppelin Upgradeable v5 (+ existing OZ / Uniswap v3 CL libs).

## Upgradeability model

- **Beacon proxy.** One `UpgradeableBeacon` (OZ) holding the implementation address; one
  `BeaconProxy` per (pool, strategy) vault instance. All instances upgrade atomically when the
  beacon owner points the beacon at a new implementation.
- **Beacon owner = timelock/multisig.** Documented, not hardcoded; the deploy script takes it
  as a parameter.
- `constructor` → `initialize()` guarded by `Initializable`. The implementation's constructor
  calls `_disableInitializers()`. Future initializers use `reinitializer(version)`.
- All former `immutable` (pool, token0, token1, decimals0, decimals1) and `constant` DEX
  addresses (positionManager, swapRouter) become **storage**, set in `initialize()`.
- ERC-7201 namespaced storage for custom state. Bases: `ERC4626Upgradeable`,
  `ERC20Upgradeable`, `ReentrancyGuardUpgradeable` (each owns its own namespace). owner /
  operator are plain (namespaced) storage, not immutable.

## Module split (one concern per file)

```
src/
  RebalancerVaultUpgradeable.sol   ERC4626 accounting + lifecycle orchestration; holds refs to
                                   strategy + adapter; setStrategy (timelocked), setDexAdapter
                                   (timelocked); ABSORBS the former VaultLens helpers.
  interfaces/
    IStrategy.sol                  computeRange / computeOptimalSwap
    IDexAdapter.sol                pool/PM/router wrapper surface
    IRebalancerVault.sol           external surface used by factory + integrators
    (existing CL interfaces unchanged)
  strategies/
    FixedWidthStrategy.sol         stateless width-based impl; half-width is an immutable arg;
                                   called via STATICCALL only; never delegatecall.
  adapters/
    CLDexAdapter.sol               stateless wrapper; addresses passed as args; writes run via
                                   DELEGATECALL in vault context (see "Adapter mechanism").
  libraries/
    OracleLib.sol                  getTwapTick, getTwapSqrtPrice, requireSpotNearTwap,
                                   isDepositAllowed (verbatim TWAP logic)
    VaultMath.sol                  computeMintSlippage, computeRemoveSlippage, computeSwapMinOut,
                                   optimal-swap math, tick floor/ceil, token0<->token1. pure/internal.
  factory/
    VaultFactory.sol               BeaconProxy deploy; registry keyed by (pool, strategy);
                                   guardian pause-all; atomic deploy→seed→initializePosition.
    (beacon: OZ UpgradeableBeacon used directly)
```

**No standalone VaultLens.** Its two helpers move onto the vault as zero-arg methods:
`sharePrice()` and `getVaultMetrics()` reading `this`. (The lens was originally split for
EIP-170 headroom; the modular library extraction reclaims that headroom since `OracleLib` /
`VaultMath` math lives outside the vault's runtime bytecode. Size monitored in `forge build`.)

## Interface signatures

### IStrategy (staticcall only)

```solidity
interface IStrategy {
    function computeRange(int24 twapTick, int24 tickSpacing)
        external view returns (int24 tickLower, int24 tickUpper);
    function computeOptimalSwap(
        uint160 sqrtP, uint160 sqrtA, uint160 sqrtB, uint256 bal0, uint256 bal1
    ) external pure returns (bool zeroForOne, uint256 amount);
}
```

`FixedWidthStrategy` stores `halfWidth` as an `immutable` (it is a plain non-proxy contract, so
immutables are fine). Three instances: 300 / 700 / 1200. `computeRange` is the verbatim
`floor(twapTick - w, spacing)` / `ceil(twapTick + w, spacing)`. **The vault re-validates the
returned ticks** (`lower < upper`, within `TickMath.MIN_TICK..MAX_TICK`) before use — it never
trusts the strategy blindly.

### IDexAdapter (reads = staticcall, writes = delegatecall)

```solidity
interface IDexAdapter {
    // reads (staticcall)
    function slot0(address pool) external view returns (uint160 sqrtPriceX96, int24 tick);
    function observe(address pool, uint32[] calldata secondsAgos)
        external view returns (int56[] memory tickCumulatives);
    function tickSpacing(address pool) external view returns (int24);
    function positions(address positionManager, uint256 tokenId) external view returns (
        int24 tickLower, int24 tickUpper, uint128 liquidity,
        uint128 tokensOwed0, uint128 tokensOwed1, address token0, address token1
    );
    // writes (run in vault context via delegatecall)
    function mint(MintArgs calldata p)
        external returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    function decreaseLiquidity(DecreaseArgs calldata p) external returns (uint256 a0, uint256 a1);
    function collect(CollectArgs calldata p) external returns (uint256 a0, uint256 a1);
    function burn(address positionManager, uint256 tokenId) external;
    function exactInputSingle(SwapArgs calldata p) external returns (uint256 amountOut);
}
```

All addresses are passed as args; the adapter holds **no storage**, so delegatecall cannot
collide with vault storage. Tokens, the position NFT, swap proceeds, and approvals never leave
the vault → custody and refund behavior are byte-for-byte identical to the monolith.

## ERC-7201 storage

Namespace: `mezo.storage.RebalancerVault`
Slot: `keccak256(abi.encode(uint256(keccak256("mezo.storage.RebalancerVault")) - 1)) & ~bytes32(0xff)`

```solidity
struct VaultStorage {
    address owner; address pendingOwner; address operator; bool paused;
    address strategy; address dexAdapter;
    address pendingStrategy; uint256 strategyChangeActiveAt;
    address pendingDexAdapter; uint256 dexAdapterChangeActiveAt;
    address pool; address token0; address token1; uint8 decimals0; uint8 decimals1;
    address positionManager; address swapRouter;
    uint256 tokenId;
    uint256 performanceFeeBps; address feeRecipient;
    uint256 pendingFeeBps; address pendingFeeRecipient; uint256 feeChangeActiveAt;
    uint256 rebalanceCount; uint256 totalFees0Earned; uint256 totalFees1Earned;
    uint32 twapSeconds; int24 maxTwapDeviationTicks; uint256 slippageBps;
    mapping(address => uint256) lastDepositBlock;
}
```

`DEAD_SHARES` remains a `constant` (chain-agnostic). Defaults set in `initialize()`.
`decimals1` is retained (stored + getter) for ABI parity. The `strategyType` enum and its
getter are **removed** (per accepted Decision 3) — strategy is now an external module.

## Accepted interface changes

1. **rebalance drops `StrategyType`.** One vault = one strategy. New signature:
   `rebalance(bool swapZeroForOne, uint256 swapAmount)`. `setStrategyWidth` is replaced by
   timelocked `setStrategy(address)`. `computeRebalanceParams()` takes no strategy arg.
   Widths preserved as `FixedWidthStrategy` constructor args.
2. **Adapter writes via delegatecall; `setDexAdapter` is timelocked** (not plain owner) because
   a delegatecall target is arbitrary code — same 2-day timelock as strategy/fee changes.
3. **`strategyType` enum getter removed**; `decimals1` retained for ABI parity.

## Factory

- `deployVault(pool, strategy, operator, owner, feeRecipient, name, symbol)` → `BeaconProxy`.
- Registry: `mapping(pool => mapping(strategy => address))` + enumerable list; reverts on
  duplicate (pool, strategy).
- Guardian role with `pauseAll()` iterating registered vaults (calls each vault's `setPaused`;
  factory must hold the guardian/pause right on each vault — vault gets a `guardian` hook).
- **Atomic deploy→seed→initializePosition**: one factory tx that (a) deploys the proxy,
  (b) pulls the seed deposit from the caller and deposits it, (c) calls `initializePosition`,
  closing the uninitialized-vault front-running window. Caller pre-approves the factory.

## Deploy scripts

- `DeployBeaconAndFactory.s.sol`: deploy implementation (constructor disables initializers) →
  `UpgradeableBeacon(impl, timelockOwner)` → `VaultFactory(beacon, ...)`.
- `DeployStrategyVaults.s.sol`: deploy `FixedWidthStrategy(300/700/1200)`, deploy the
  `CLDexAdapter`, then call the factory's atomic flow three times (TIGHT/MEDIUM/WIDE).

## Testing

- **Parity:** re-point the existing unit/fuzz/integration/invariant suites at the upgradeable
  vault (behind a proxy). Add focused parity tests asserting identical results for deposit,
  depositToken1, withdraw, redeem, initializePosition, rebalance (incl. fee isolation), and
  **every revert/guard** (ZeroAmount, SameBlock, PriceDeviatedFromTwap, ExceedsMax*, TimelockActive, …).
- **Beacon upgrade test:** deploy, seed state (deposits + a position), upgrade the beacon to a
  V2 impl, assert all storage survives and behavior continues.
- **Storage-layout snapshot:** `forge inspect ... storageLayout` committed; CI diff guard.

## Deliverables

1. Refactored contracts in the layout above.
2. Foundry parity tests + beacon-upgrade test + storage-layout snapshot.
3. Deploy scripts (beacon + impl + factory, then the 3 strategy vaults).
4. `STORAGE_LAYOUT.md` (ERC-7201 namespaces) and `UPGRADE.md` (proxy-upgrade vs strategy-swap).
5. `REVIEW.md` listing every spot where behavior could have drifted, confirming it didn't.

## Process

Incremental, one module at a time, `forge build` after each. Extract logic verbatim; adapt
signatures only at module boundaries. NatSpec on every external/public fn and each module header.

Build order: (1) add OZ Upgradeable dep + remapping → (2) libraries (OracleLib, VaultMath) →
(3) interfaces → (4) FixedWidthStrategy → (5) CLDexAdapter → (6) RebalancerVaultUpgradeable →
(7) factory + beacon → (8) tests → (9) scripts → (10) docs.

## New dependency

`openzeppelin-contracts-upgradeable` is **not** currently in `lib/`. Add it (v5, matching the
existing OZ v5) and the remapping
`@openzeppelin/contracts-upgradeable/=lib/openzeppelin-contracts-upgradeable/contracts/`.
