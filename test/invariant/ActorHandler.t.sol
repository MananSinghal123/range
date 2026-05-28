// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import "../BaseTest.sol";

contract ActorHandler is BaseTest {
    address public immutable actor;
    uint256 public ghost_sharesOwned;
    uint256 public ghost_token0Deposited;
    uint256 public ghost_token0Redeemed;
    uint256 public numCalls;

    constructor(address _actor) {
        setUp();
        actor = _actor;
    }

    function deposit(uint256 assets) external {
        numCalls++;

        // Guard: whenNotPaused
        if (vault.paused()) return;

        uint256 supply = vault.totalSupply();
        uint256 totalVal = vault.totalAssets();
        uint256 balance0 = token0.balanceOf(actor);
        uint256 maxDep = vault.maxDeposit(actor);

        if (balance0 == 0 || maxDep == 0) return;

        uint256 minDeposit = supply == 0 ? DEAD_SHARES + 1 : 1;

        uint256 upperBound = balance0 < maxDep ? balance0 : maxDep;
        if (upperBound < minDeposit) return;

        assets = bound(assets, minDeposit, upperBound);

        if (supply > 0 && totalVal == 0) return;

        if (supply > 0 && totalVal > 0) {
            if (vault.previewDeposit(assets) == 0) return;
        }

        vm.startPrank(actor);
        uint256 shares = vault.deposit(assets, actor);
        vm.stopPrank();

        ghost_token0Deposited += assets;
        ghost_sharesOwned += shares;
    }

    function redeem(uint256 sharesPct) external {
        numCalls++;

        if (vault.paused()) return;

        uint256 shares = vault.balanceOf(actor);
        if (shares == 0) return;

        uint256 maxRedeemable = vault.maxRedeem(actor);
        if (maxRedeemable == 0) return;

        sharesPct = bound(sharesPct, 1, 100);
        uint256 toRedeem = bound((shares * sharesPct) / 100, 1, maxRedeemable);

        // Guard: ZeroAmount — vault reverts if proportional payout is 0.
        if (vault.previewRedeem(toRedeem) == 0) return;

        uint256 token0Before = token0.balanceOf(actor);

        // owner_ == actor: actor owns their own shares, no allowance path.
        vm.startPrank(actor);
        vault.redeem(toRedeem, actor, actor);
        vm.stopPrank();

        ghost_token0Redeemed += token0.balanceOf(actor) - token0Before;
        ghost_sharesOwned -= toRedeem;
    }

    function depositToken1(uint256 amount) external {
        numCalls++;

        if (vault.paused()) return;
        if (vault.totalSupply() > 0 && vault.totalAssets() == 0) return;

        uint256 token0Equivalent = vault.previewDepositToken1(amount);

        if (token0Equivalent == 0) return;

        uint256 balance1 = token1.balanceOf(actor);
        if (balance1 == 0) return;

        amount = bound(amount, 1, balance1);

        vm.startPrank(actor);
        uint256 shares = vault.depositToken1(amount, actor);
        vm.stopPrank();

        ghost_sharesOwned += shares;

        uint256 supply = vault.totalSupply();
        if (supply > shares) {
            ghost_token0Deposited += vault.convertToAssets(shares);
        }
    }
}
