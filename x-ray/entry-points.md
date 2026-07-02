# Entry Point Map

> Mezo Rebalancer Vault | 27 entry points | 6 permissionless | 4 role-gated | 15 admin-only

---

## Protocol Flow Paths

### Setup (Owner / Factory)

`Factory.deployVault()` → `Vault.initialize()` → `Vault.initializePosition()`  ◄── needs idle token0/token1

`Factory.deploySeedAndInitialize()` bundles: `deployVault` → `deposit(seed)` → `initializePosition` → `transferOwnership(realOwner)` in one owner call.

### User Flow

`[setup above]` → `Vault.deposit()` / `Vault.mint()` / `Vault.depositToken1()`  ◄── spot must be near TWAP (G-21)
                          └─→ `Vault.withdraw()` / `Vault.redeem()`  ◄── not same block as deposit (G-8/G-9), spot near TWAP

### Maintenance (Operator / Keeper)

`[deposit above]` → [spot near TWAP] → `Vault.rebalance()`  ◄── position must exist (G-4)
`[position exists]` → `Vault.collectFees()`

`VaultLens.computeRebalanceParams()` (view) supplies the `swapZeroForOne` / `swapAmount` args the operator passes to `rebalance`.

### Emergency (Guardian)

`Factory.pauseAll()` → per-vault `Vault.pauseByGuardian()`  (Factory is each vault's guardian)

### Governance (Owner)

`proposePerformanceFee()` → [2-day timelock, I-8] → `applyPerformanceFee()`

---

## Permissionless

### `RebalancerVaultUpgradeable.deposit()`

| Aspect | Detail |
|--------|--------|
| Visibility | public, nonReentrant, whenNotPaused |
| Caller | Any depositor |
| Parameters | assets (user-controlled), receiver (user-controlled) |
| Call chain | `→ _requireSpotNearTwap() → OracleLib.requireSpotNearTwap() → IERC20.safeTransferFrom() → _mint()` |
| State modified | `lastDepositBlock`, `_balances`, `_totalSupply` |
| Value flow | token0: sender → Vault |
| Reentrancy guard | yes |

### `RebalancerVaultUpgradeable.mint()`

| Aspect | Detail |
|--------|--------|
| Visibility | public, nonReentrant, whenNotPaused |
| Caller | Any depositor |
| Parameters | shares (user-controlled), receiver (user-controlled) |
| Call chain | `→ _requireSpotNearTwap() → previewMint() → IERC20.safeTransferFrom() → _mint()` |
| State modified | `lastDepositBlock`, `_balances`, `_totalSupply` |
| Value flow | token0: sender → Vault |
| Reentrancy guard | yes |

### `RebalancerVaultUpgradeable.depositToken1()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant, whenNotPaused |
| Caller | Any depositor |
| Parameters | token1Amount (user-controlled), receiver (user-controlled) |
| Call chain | `→ _requireSpotNearTwap() → IERC20.safeTransferFrom() → VaultMath.token1ToToken0() → OracleLib.getTwapSqrtPrice() → _mint()` |
| State modified | `lastDepositBlock`, `_balances`, `_totalSupply` |
| Value flow | token1: sender → Vault |
| Reentrancy guard | yes |

### `RebalancerVaultUpgradeable.withdraw()`

| Aspect | Detail |
|--------|--------|
| Visibility | public, nonReentrant, whenNotPaused |
| Caller | Share owner / approved spender |
| Parameters | assets (user-controlled), receiver (user-controlled), owner_ (user-controlled) |
| Call chain | `→ _requireSpotNearTwap() → previewWithdraw() → _removeProportionalLiquidity() → CLDexAdapter.decreaseLiquidity()/collect() [delegatecall] → _executeSwap() → _burn() → IERC20.safeTransfer()` |
| State modified | `_balances`, `_totalSupply`, `tokenId` position liquidity |
| Value flow | token0: Vault → receiver |
| Reentrancy guard | yes |

### `RebalancerVaultUpgradeable.redeem()`

| Aspect | Detail |
|--------|--------|
| Visibility | public, nonReentrant, whenNotPaused |
| Caller | Share owner / approved spender |
| Parameters | shares (user-controlled), receiver (user-controlled), owner_ (user-controlled) |
| Call chain | `→ _requireSpotNearTwap() → _removeProportionalLiquidity() → CLDexAdapter.decreaseLiquidity()/collect() [delegatecall] → _burn() → IERC20.safeTransfer() (token0 + token1)` |
| State modified | `_balances`, `_totalSupply`, `tokenId` position liquidity, `totalFees*Earned` |
| Value flow | token0 + token1: Vault → receiver |
| Reentrancy guard | yes |

### `CLDexAdapter` externals (`mint` / `decreaseLiquidity` / `collect` / `burn` / `exactInputSingle`)

| Aspect | Detail |
|--------|--------|
| Visibility | external (no access control) |
| Caller | Intended: the vault via `delegatecall`. The deployed adapter is also directly callable. |
| Parameters | struct args (caller-controlled) |
| Call chain | `→ INonfungiblePositionManager.* / ICLSwapRouter.exactInputSingle()` |
| State modified | None in adapter (stateless); operates on the caller's own token/approval context |
| Value flow | Only moves the *caller's* tokens; direct calls on the standalone adapter act on its empty context |
| Reentrancy guard | no |

---

## Role-Gated

### `Operator`

#### `RebalancerVaultUpgradeable.rebalance()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant, whenNotPaused, positionExists |
| Caller | Operator (keeper) |
| Parameters | swapZeroForOne (keeper-provided), swapAmount (keeper-provided) |
| Call chain | `→ _requireSpotNearTwap() → _rebalanceRemoveFeeCollectBurn() → CLDexAdapter.decreaseLiquidity/collect/burn [delegatecall] → _executeSwap() → _rebalanceMintNew() → IStrategy.computeRange() → CLDexAdapter.mint() [delegatecall]` |
| State modified | `tokenId`, `rebalanceCount`, `totalFees*Earned` |
| Value flow | Internal (swap + re-mint); performance fee → feeRecipient |
| Reentrancy guard | yes |

#### `RebalancerVaultUpgradeable.collectFees()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant, whenNotPaused, positionExists |
| Caller | Operator (keeper) |
| Parameters | amount0Min (keeper-provided), amount1Min (keeper-provided) |
| Call chain | `→ CLDexAdapter.decreaseLiquidity(0)/collect [delegatecall] → _deductPerformanceFee() → IERC20.safeTransfer()` |
| State modified | `totalFees0Earned`, `totalFees1Earned` |
| Value flow | performance fee → feeRecipient; remainder stays idle |
| Reentrancy guard | yes |

### `Guardian`

#### `RebalancerVaultUpgradeable.pauseByGuardian()`

| Aspect | Detail |
|--------|--------|
| Visibility | external (internal `msg.sender == guardian` check) |
| Caller | Guardian (the VaultFactory) |
| Parameters | none |
| Call chain | `→ sets paused = true` |
| State modified | `paused` |
| Value flow | none |
| Reentrancy guard | no |

### `pendingOwner`

#### `RebalancerVaultUpgradeable.acceptOwnership()`

| Aspect | Detail |
|--------|--------|
| Visibility | external (internal `msg.sender == pendingOwner` check) |
| Caller | Pending owner |
| Parameters | none |
| Call chain | `→ owner = pendingOwner; pendingOwner = 0` |
| State modified | `owner`, `pendingOwner` |
| Value flow | none |
| Reentrancy guard | no |

### `Factory Guardian`

#### `VaultFactory.pauseAll()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, onlyGuardian |
| Caller | Factory guardian |
| Parameters | none |
| Call chain | `→ loop IRebalancerVault.pauseByGuardian()` over allVaults |
| State modified | `paused` on every vault |
| Value flow | none |
| Reentrancy guard | no |

---

## Admin-Only

| Contract | Function | Parameters | State Modified |
|----------|----------|------------|----------------|
| Vault | `initializePosition()` | ticks, amounts, mins | `tokenId` (mints NFT) |
| Vault | `transferOwnership()` | newOwner | `pendingOwner` |
| Vault | `setOperator()` | newOperator | `operator` |
| Vault | `setPaused()` | _paused | `paused` |
| Vault | `setGuardian()` | newGuardian | `guardian` |
| Vault | `setStrategy()` | newStrategy | `strategy` |
| Vault | `setDexAdapter()` | newAdapter | `dexAdapter` |
| Vault | `proposePerformanceFee()` | bps, recipient | `pendingFeeBps`, `pendingFeeRecipient`, `feeChangeActiveAt` |
| Vault | `applyPerformanceFee()` | — | `performanceFeeBps`, `feeRecipient` |
| Vault | `sweepToken()` | token, to | transfers non-core token out |
| Vault | `setTwapSeconds()` | seconds_ | `twapSeconds` |
| Vault | `setMaxTwapDeviationTicks()` | ticks | `maxTwapDeviationTicks` |
| Vault | `setSlippageBps()` | bps | `slippageBps` |
| Factory | `deployVault()` | pool, strategy, roles, name/symbol | `vaultFor`, `allVaults` |
| Factory | `deploySeedAndInitialize()` | + seed, ticks, mins | deploys, seeds, inits, transfers ownership |
| Factory | `setGuardian()` | newGuardian | `guardian` |
| Factory (Beacon) | `upgradeTo()` | newImplementation | beacon implementation (all vaults) |

---

## Initialization

- `RebalancerVaultUpgradeable.initialize(InitParams)` — `initializer` modifier; called once via `BeaconProxy` constructor from `VaultFactory._deploy`. Sets all roles, pool/token wiring, and default params (fee 1000bps, twap 300s, deviation 200 ticks, slippage 50bps). The implementation contract's constructor calls `_disableInitializers()`.
