// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import "../Base.sol";
import {Properties} from "../Properties.sol";

/// @notice Handles the interaction with RebalancerVaultUpgradeable.
///
/// Caller model: owner == operator == guardian == address(this) (the FuzzTester).
///  - User flows (deposit/mint/depositToken1/withdraw/redeem/transfer) prank as an Actor.
///  - Operator flows (rebalance/collectFees) and admin flows (secondary) run as
///    address(this), which IS the operator/owner, so they need no prank.
abstract contract RebalancerVaultUpgradeableHandler is Properties {

    // ――――――――――――――――――――――――― Clamped ――――――――――――――――――――――――――

    function rebalancerVaultUpgradeable_deposit_clamped(uint256 assets, address receiver) public {
        actor = toActor(receiver); // caller & receiver are the same actor
        uint256 bal = token0.balanceOf(actor);
        if (bal == 0) return;
        assets = clampBetween(assets, 1, bal);
        rebalancerVaultUpgradeable_deposit(assets, actor);
    }

    /// @dev Near-zero / sub-DEAD_SHARES boundary — exercises zero-share and min-deposit reverts.
    function rebalancerVaultUpgradeable_deposit_smallAmount(uint256 assets, address receiver) public {
        actor = toActor(receiver);
        assets = clampBetween(assets, 1, DEAD_SHARES * 4);
        rebalancerVaultUpgradeable_deposit(assets, actor);
    }

    function rebalancerVaultUpgradeable_mint_clamped(uint256 shares, address receiver) public {
        actor = toActor(receiver);
        uint256 bal = token0.balanceOf(actor);
        if (bal == 0) return;
        uint256 maxShares = vault.convertToShares(bal);
        if (maxShares == 0) return;
        shares = clampBetween(shares, 1, maxShares);
        rebalancerVaultUpgradeable_mint(shares, actor);
    }

    function rebalancerVaultUpgradeable_depositToken1_clamped(uint256 token1Amount, address receiver) public {
        actor = toActor(receiver);
        uint256 bal = token1.balanceOf(actor);
        if (bal == 0) return;
        token1Amount = clampBetween(token1Amount, 1, bal);
        rebalancerVaultUpgradeable_depositToken1(token1Amount, actor);
    }

    function rebalancerVaultUpgradeable_withdraw_clamped(uint256 assets, address receiver, address owner_) public {
        actor = toActor(owner_); // caller must own the shares
        uint256 maxW = vault.maxWithdraw(actor);
        if (maxW == 0) return;
        assets = clampBetween(assets, 1, maxW);
        rebalancerVaultUpgradeable_withdraw(assets, toActor(receiver), actor);
    }

    /// @dev Full-amount boundary — withdraw the entire redeemable value.
    function rebalancerVaultUpgradeable_withdraw_full(address receiver, address owner_) public {
        actor = toActor(owner_);
        uint256 maxW = vault.maxWithdraw(actor);
        if (maxW == 0) return;
        rebalancerVaultUpgradeable_withdraw(maxW, toActor(receiver), actor);
    }

    function rebalancerVaultUpgradeable_redeem_clamped(uint256 shares, address receiver, address owner_) public {
        actor = toActor(owner_);
        uint256 maxR = vault.maxRedeem(actor);
        if (maxR == 0) return;
        shares = clampBetween(shares, 1, maxR);
        rebalancerVaultUpgradeable_redeem(shares, toActor(receiver), actor);
    }

    /// @dev Full-amount boundary — redeem all shares owned by the actor.
    function rebalancerVaultUpgradeable_redeem_full(address receiver, address owner_) public {
        actor = toActor(owner_);
        uint256 maxR = vault.maxRedeem(actor);
        if (maxR == 0) return;
        rebalancerVaultUpgradeable_redeem(maxR, toActor(receiver), actor);
    }

    function rebalancerVaultUpgradeable_rebalance_clamped(bool swapZeroForOne, uint256 swapAmount) public {
        // Bound the swap to the vault's idle balance of the input token so the
        // router transfer does not revert on insufficient balance.
        uint256 idle = swapZeroForOne
            ? token0.balanceOf(address(vault))
            : token1.balanceOf(address(vault));
        swapAmount = idle == 0 ? 0 : clampBetween(swapAmount, 0, idle);
        rebalancerVaultUpgradeable_rebalance(swapZeroForOne, swapAmount);
    }

    function rebalancerVaultUpgradeable_collectFees_clamped(uint256 amount0Min, uint256 amount1Min) public {
        // Min-out floors: keep low so the collect is not spuriously blocked.
        amount0Min = clampBetween(amount0Min, 0, 1e6);
        amount1Min = clampBetween(amount1Min, 0, 1e6);
        rebalancerVaultUpgradeable_collectFees(amount0Min, amount1Min);
    }

    /// @dev Simulates swap-fee growth on the live CL position by crediting the
    ///      mock position manager's owed fees. Drives the fee-conservation (I-1),
    ///      performance-fee, and share-price-from-fees paths that otherwise never
    ///      fire (a fresh mock position accrues nothing).
    function rebalancerVaultUpgradeable_accrueFees(uint256 fee0, uint256 fee1) public {
        uint256 id = vault.tokenId();
        if (id == 0) return;
        fee0 = clampBetween(fee0, 0, 1_000e18);
        fee1 = clampBetween(fee1, 0, 100e8);
        pm.setPendingFees(id, fee0, fee1);
    }

    // ―――――――――――――――――――― Donation handlers ――――――――――――――――――――
    // Donations inflate totalAssets via balanceOf() with no internal-accounting
    // counterpart — the exact surface of I-12 / E-1 (share-price manipulation).

    function rebalancerVaultUpgradeable_donateToken0(uint256 amount) public {
        uint256 bal = token0.balanceOf(actor);
        if (bal == 0) return;
        amount = clampBetween(amount, 1, bal);
        vm.prank(actor);
        token0.transfer(address(vault), amount);
    }

    function rebalancerVaultUpgradeable_donateToken1(uint256 amount) public {
        uint256 bal = token1.balanceOf(actor);
        if (bal == 0) return;
        amount = clampBetween(amount, 1, bal);
        vm.prank(actor);
        token1.transfer(address(vault), amount);
    }

    function rebalancerVaultUpgradeable_donateETH(uint256 amount) public {
        if (actor.balance == 0) return;
        amount = clampBetween(amount, 1, actor.balance);
        Actor(payable(actor)).forceSendETH(address(vault), amount);
    }

    // ――――――――――――――――― Secondary dispatcher (admin) ―――――――――――――――――

    function rebalancerVaultUpgradeable_secondary(uint8 selector, uint256 arg0, address arg1) public {
        selector = uint8(selector % 7);
        if (selector == 0) _rebalancerVaultUpgradeable_transfer(arg1, arg0);
        else if (selector == 1) _rebalancerVaultUpgradeable_setPaused(arg0 % 2 == 0);
        else if (selector == 2) _rebalancerVaultUpgradeable_proposePerformanceFee(arg0, arg1);
        else if (selector == 3) _rebalancerVaultUpgradeable_applyPerformanceFee();
        else if (selector == 4) _rebalancerVaultUpgradeable_setSlippageBps(arg0);
        else if (selector == 5) _rebalancerVaultUpgradeable_setTwapSeconds(uint32(arg0));
        else _rebalancerVaultUpgradeable_setMaxTwapDeviationTicks(arg0);
    }

    // ―――――――――――――――――――――――― Unclamped ―――――――――――――――――――――――――

    function rebalancerVaultUpgradeable_deposit(uint256 assets, address receiver) public asActor {
        vault.deposit(assets, receiver);
    }

    function rebalancerVaultUpgradeable_mint(uint256 shares, address receiver) public asActor {
        vault.mint(shares, receiver);
    }

    function rebalancerVaultUpgradeable_depositToken1(uint256 token1Amount, address receiver) public asActor {
        vault.depositToken1(token1Amount, receiver);
    }

    function rebalancerVaultUpgradeable_withdraw(uint256 assets, address receiver, address owner_) public asActor {
        vault.withdraw(assets, receiver, owner_);
    }

    function rebalancerVaultUpgradeable_redeem(uint256 shares, address receiver, address owner_) public asActor {
        vault.redeem(shares, receiver, owner_);
    }

    // Operator context (msg.sender == address(this) == operator): no prank.
    function rebalancerVaultUpgradeable_rebalance(bool swapZeroForOne, uint256 swapAmount) public {
        vault.rebalance(swapZeroForOne, swapAmount);
    }

    function rebalancerVaultUpgradeable_collectFees(uint256 amount0Min, uint256 amount1Min) public {
        vault.collectFees(amount0Min, amount1Min);
    }

    // Share transfer is a user action → prank as the actor.
    function _rebalancerVaultUpgradeable_transfer(address to, uint256 value) internal {
        uint256 bal = vault.balanceOf(actor);
        if (bal == 0) return;
        value = clampBetween(value, 0, bal);
        vm.prank(actor);
        vault.transfer(toActor(to), value);
    }

    // Admin context (msg.sender == address(this) == owner): no prank.
    function _rebalancerVaultUpgradeable_setPaused(bool _paused) internal {
        vault.setPaused(_paused);
    }

    function _rebalancerVaultUpgradeable_proposePerformanceFee(uint256 bps, address recipient) internal {
        bps = clampBetween(bps, 0, 1000); // G-14: <= 10%
        if (recipient == address(0)) recipient = feeRecipient;
        vault.proposePerformanceFee(bps, recipient);
    }

    function _rebalancerVaultUpgradeable_applyPerformanceFee() internal {
        vault.applyPerformanceFee();
    }

    function _rebalancerVaultUpgradeable_setSlippageBps(uint256 bps) internal {
        bps = clampBetween(bps, 0, 500); // G-19: <= 5%
        vault.setSlippageBps(bps);
    }

    function _rebalancerVaultUpgradeable_setTwapSeconds(uint32 seconds_) internal {
        // G-17: >= 60. Keep below the timestamp floor so observe() never underflows.
        seconds_ = uint32(clampBetween(seconds_, 60, 3600));
        vault.setTwapSeconds(seconds_);
    }

    function _rebalancerVaultUpgradeable_setMaxTwapDeviationTicks(uint256 ticks) internal {
        // G-18: (0, 1000].
        ticks = clampBetween(ticks, 1, 1000);
        vault.setMaxTwapDeviationTicks(int24(uint24(ticks)));
    }
}
