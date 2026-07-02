# Coverage Targets

Fuzz profile: via_ir required (stack too deep), optimizer_runs=0 — coverage deflated ~10%, targets adjusted (ir-no-opt column).

Build command for all fuzz steps: `FOUNDRY_PROFILE=fuzz forge build`

## Per-contract targets

| Contract | Role | Target (ir-no-opt) |
|---|---|---|
| RebalancerVaultUpgradeable | Core vault logic | 70%+ |
| CLDexAdapter | Peripheral adapter (delegatecalled) | 40%+ |
| VaultMath | Math library | inherited from callers |
| OracleLib | Oracle/TWAP library | inherited from callers |
| Strategy | Stateless range module | inherited from callers |

## Skip justifications

- `initialize` / `initializePosition` — one-shot setup, executed once in `Base.setup()`, not fuzzed.
- Owner rug levers (`setStrategy`/`setDexAdapter`/`setGuardian`/`sweepToken`/`transferOwnership`/`acceptOwnership`) — excluded from handlers (owner-trust boundary, repointing delegatecall targets to random code just breaks the harness).
- `VaultFactory` / beacon `upgradeTo` — deploy/upgrade infra, wired directly in setup.
- Fee-on-transfer / rebasing branches — MockERC20 is standard; not reachable in-harness.

## Cycle 1 (2026-07-02)

| Contract | Role | Target | Hit | Status |
|---|---|---|---|---|
| RebalancerVaultUpgradeable | Core vault (selected flows) | 70% | 72% (419/580) | ✅ |
| CLDexAdapter | Peripheral adapter | 40% | 91% (54/59) | ✅ |
| OracleLib | Library | inherited | 95% (23/24) | ✅ |
| VaultStorageLib | Library | inherited | 100% (5/5) | ✅ |
| VaultMath | Library | inherited | 43% (32/74) | ⚠️ inherent |
| Strategy | Library | inherited | 25% (2/8) | ⚠️ inherent |
| VaultLens | Off-chain view helper | excluded | 0% | ⏭️ skip |
| VaultFactory | Setup infra | excluded | 0% | ⏭️ skip |

Run stats: ~96k calls, 12,654 branches, 23/23 handler assertion tests passed, 0 property/assertion failures, 0 crashes.

Decision: PROCEED. The selected-entry-point contract (RebalancerVaultUpgradeable) meets its 70% target. Remaining gaps are inherent to the fuzzed surface:
- VaultMath 43%: uncovered lines are dominated by `computeOptimalSwap`/`computeRebalanceParams`, reachable only via the off-chain `VaultLens` (the on-chain `rebalance` takes an operator-supplied `swapAmount` and never calls `computeOptimalSwap`). Also extreme-value overflow branches.
- Strategy 25% (2/8 lines): the single `computeRange` path is hit via rebalance; the remainder is a defensive branch.
- VaultLens 0%: off-chain read helper, no state transitions — not a fuzz target by design.
- VaultFactory 0%: beacon/deploy/upgrade infra, wired directly in `Base.setup()`.
