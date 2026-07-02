// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../BaseTest.sol";

/// @notice ERC-4626 spec/edge-case coverage that doesn't fit the lifecycle-flow
///         files: rounding direction, max*/preview* boundaries, inflation-attack
///         resistance, dead-share invariants, and the two known same-block-guard
///         gaps documented in PROPERTIES.md (SP-19, SP-20).
/// @dev Amount conventions: token0 = MUSD (18 decimals), token1 = BTC (8 decimals).
///      Per PROPERTIES.md's harness note, this vault is NOT a faithful ERC-4626:
///      `redeem` can pay out both token0 and token1, and `withdraw` can revert on
///      a token0 shortfall even when `assets <= maxWithdraw`. Tests below treat
///      those divergences as documented behavior, not bugs.
contract Erc4626EdgeCasesTest is BaseTest {
    int24 internal LO;
    int24 internal HI;

    function setUp() public override {
        super.setUp();
        LO = ((TICK_100K - 2000) / TICK_SPACING) * TICK_SPACING;
        HI = ((TICK_100K + 2000) / TICK_SPACING) * TICK_SPACING;
    }

    // ── asset() / decimals() spec compliance (GL-27) ────────────────────────────

    function test_asset_returnsToken0() public view {
        assertEq(vault.asset(), address(token0));
    }

    function test_decimals_matchesToken0() public view {
        assertEq(vault.decimals(), token0.decimals());
    }

    // ── convertToShares / convertToAssets rounding & zero-state (GL-05, GL-29, GL-30) ──

    function test_convertToShares_zeroInputIsZero() public {
        assertEq(vault.convertToShares(0), 0);
        _initialDeposit(10e18);
        assertEq(vault.convertToShares(0), 0);
    }

    function test_convertToAssets_zeroInputIsZero() public {
        assertEq(vault.convertToAssets(0), 0);
        _initialDeposit(10e18);
        assertEq(vault.convertToAssets(0), 0);
    }

    function test_convertToShares_emptyVaultIsIdentity() public view {
        // Pristine vault: supply == 0 → convertToShares is 1:1 (unlike
        // previewDeposit, which additionally carves out DEAD_SHARES).
        assertEq(vault.convertToShares(12345), 12345);
    }

    function test_convertToAssets_emptyVaultIsIdentity() public view {
        assertEq(vault.convertToAssets(12345), 12345);
    }

    function test_convertRoundtrip_neverInflationary() public {
        _initialDeposit(10e18);
        vm.prank(bob);
        vault.deposit(3e18, bob);

        for (uint256 i = 0; i < 5; i++) {
            uint256 x = (7e17 * (i + 1));
            assertLe(vault.convertToAssets(vault.convertToShares(x)), x);
            uint256 s = vault.balanceOf(alice) / (i + 1);
            assertLe(vault.convertToShares(vault.convertToAssets(s)), s);
        }
    }

    function test_convertToShares_monotonicNonDecreasing() public {
        _initialDeposit(10e18);
        assertLe(vault.convertToShares(1e18), vault.convertToShares(2e18));
        assertLe(vault.convertToShares(2e18), vault.convertToShares(3e18));
    }

    // ── Dead-share invariant (GL-02, GL-16) ──────────────────────────────────────

    function test_deadShares_survivesFullExit() public {
        assertEq(vault.totalSupply(), 0);

        _initialDeposit(10e18);
        assertEq(vault.balanceOf(address(0xdead)), DEAD_SHARES);

        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);

        // Non-dead supply is fully drained, but the dead shares are permanent.
        assertEq(vault.totalSupply(), DEAD_SHARES);
        assertEq(vault.balanceOf(address(0xdead)), DEAD_SHARES);
    }

    function test_deadShares_vaultReseedableAfterFullExit() public {
        _initialDeposit(10e18);
        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);
        assertEq(vault.totalSupply(), DEAD_SHARES);

        // A fresh deposit after full drain must not be permanently bricked
        // (ADV-08 / SP-18): totalValBefore is the dust the dead shares still
        // represent, not zero, so the `supply==0` dead-share path is skipped
        // and ordinary proportional minting takes over.
        vm.prank(bob);
        uint256 shares = vault.deposit(5e18, bob);
        assertGt(shares, 0);
        assertGt(vault.balanceOf(bob), 0);
    }

    // ── Donation / inflation-attack resistance (GL-20, SP-16, SP-17) ─────────────

    function test_donationBeforeFirstDeposit_doesNotBrickPreviewDeposit() public {
        // Attacker donates token0 directly to the empty vault before anyone
        // deposits through the ERC-4626 interface.
        vm.prank(owner);
        token0.transfer(address(vault), 1_000_000e18);

        // previewDeposit must stay usable and non-zero for a reasonable
        // deposit — the DEAD_SHARES mechanism is keyed off `supply == 0`,
        // not off totalAssets, so a pre-deposit donation cannot poison it.
        assertGt(vault.previewDeposit(1e18), 0);
        assertTrue(vault.previewMint(1) != type(uint256).max);
    }

    function test_selfDonation_noProfitForDonor() public {
        _initialDeposit(10e18);
        vm.roll(block.number + 1);

        uint256 valueBefore = vault.convertToAssets(vault.balanceOf(alice)) +
            token0.balanceOf(alice);

        // Alice donates idle token0 directly to the vault (bypassing deposit).
        vm.prank(alice);
        token0.transfer(address(vault), 1e18);
        vm.roll(block.number + 1);

        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);

        uint256 valueAfter = token0.balanceOf(alice);
        // Donating to yourself then exiting must not yield a net profit
        // relative to your pre-donation holdings (principal + shares' value).
        assertLe(valueAfter, valueBefore);
    }

    function test_donation_benefitsExistingHoldersProRata() public {
        _initialDeposit(10e18);
        vm.prank(bob);
        vault.deposit(10e18, bob);

        uint256 bobAssetsBefore = vault.convertToAssets(vault.balanceOf(bob));

        vm.prank(owner);
        token0.transfer(address(vault), 2e18);

        uint256 bobAssetsAfter = vault.convertToAssets(vault.balanceOf(bob));
        assertGt(bobAssetsAfter, bobAssetsBefore);
    }

    // ── previewDeposit/previewMint vs actual (SP-06) ─────────────────────────────

    function test_previewDeposit_neverOverstatesActualShares() public {
        _initialDeposit(10e18);
        uint256 preview = vault.previewDeposit(3e18);
        vm.prank(bob);
        uint256 actual = vault.deposit(3e18, bob);
        assertLe(preview, actual);
    }

    function test_previewMint_neverUnderstatesActualAssets() public {
        _initialDeposit(10e18);
        uint256 preview = vault.previewMint(3e18);
        vm.prank(bob);
        uint256 actual = vault.mint(3e18, bob);
        assertGe(preview, actual);
    }

    function test_previewWithdraw_neverUnderstatesActualShares() public {
        _initialDeposit(10e18);
        uint256 preview = vault.previewWithdraw(2e18);
        vm.roll(block.number + 1);
        uint256 sharesBefore = vault.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(2e18, alice, alice);
        uint256 burned = sharesBefore - vault.balanceOf(alice);
        assertGe(preview, burned);
    }

    // ── max* boundary reverts (ExceedsMax*) ──────────────────────────────────────

    function test_mint_exceedsMaxMintReverts() public {
        _initialDeposit(10e18);
        vm.prank(owner);
        vault.setPaused(true);
        vm.prank(alice);
        vm.expectRevert();
        vault.mint(1, alice);
    }

    function test_maxDeposit_zeroWhenPaused() public {
        vm.prank(owner);
        vault.setPaused(true);
        assertEq(vault.maxDeposit(alice), 0);
    }

    function test_maxMint_zeroWhenPaused() public {
        vm.prank(owner);
        vault.setPaused(true);
        assertEq(vault.maxMint(alice), 0);
    }

    function test_maxWithdraw_zeroWhenPaused() public {
        _initialDeposit(10e18);
        vm.prank(owner);
        vault.setPaused(true);
        assertEq(vault.maxWithdraw(alice), 0);
    }

    function test_maxRedeem_equalsBalanceWhenNotPaused() public {
        _initialDeposit(10e18);
        assertEq(vault.maxRedeem(alice), vault.balanceOf(alice));
    }

    function test_maxRedeem_zeroWhenPaused() public {
        _initialDeposit(10e18);
        vm.prank(owner);
        vault.setPaused(true);
        assertEq(vault.maxRedeem(alice), 0);
    }

    function test_maxWithdraw_matchesConvertToAssetsOfBalance() public {
        _initialDeposit(10e18);
        assertEq(
            vault.maxWithdraw(alice),
            vault.convertToAssets(vault.balanceOf(alice))
        );
    }

    // ── NoAssets guard: supply > 0 but totalAssets() == 0 ────────────────────────

    function test_deposit_revertsWhenSupplyPositiveButAssetsZero() public {
        _initialDeposit(10e18);
        vm.roll(block.number + 1);

        // Drain the vault's entire token0 balance out from under it (no
        // position, no idle token1) so totalAssets() == 0 while supply > 0.
        uint256 vaultBal = token0.balanceOf(address(vault));
        token0.burn(address(vault), vaultBal);
        assertEq(vault.totalAssets(), 0);

        vm.prank(bob);
        vm.expectRevert(RebalancerVaultUpgradeable.NoAssets.selector);
        vault.deposit(1e18, bob);
    }

    function test_mint_revertsWhenSupplyPositiveButAssetsZero() public {
        _initialDeposit(10e18);
        vm.roll(block.number + 1);

        uint256 vaultBal = token0.balanceOf(address(vault));
        token0.burn(address(vault), vaultBal);
        assertEq(vault.totalAssets(), 0);

        vm.prank(bob);
        vm.expectRevert(RebalancerVaultUpgradeable.NoAssets.selector);
        vault.mint(1e18, bob);
    }

    // ── ETH / non-asset donation non-interference (GL-24) ────────────────────────

    function test_forceSentEth_doesNotAffectTotalAssetsOrSharePrice() public {
        _initialDeposit(10e18);
        uint256 taBefore = vault.totalAssets();
        uint256 previewBefore = vault.previewDeposit(1e18);

        vm.deal(address(this), 5 ether);
        (bool ok, ) = address(vault).call{value: 5 ether}("");
        assertTrue(ok);

        assertEq(vault.totalAssets(), taBefore);
        assertEq(vault.previewDeposit(1e18), previewBefore);
    }

    // ── vault.transfer conserves supply (GL-25) ──────────────────────────────────

    function test_transfer_conservesTotalSupplyAndBalances() public {
        _initialDeposit(10e18);
        uint256 supplyBefore = vault.totalSupply();
        uint256 amt = vault.balanceOf(alice) / 3;

        vm.prank(alice);
        vault.transfer(bob, amt);

        assertEq(vault.totalSupply(), supplyBefore);
        assertEq(vault.balanceOf(bob), amt);
    }

    // ── Known gap: same-block guard bypassable via share transfer (SP-19) ───────
    // PROPERTIES.md SP-19: `lastDepositBlock` is stamped on deposit/mint/
    // depositToken1 but NOT on `transfer`. A depositor can hand shares to a
    // fresh address in the same block and that address's `lastDepositBlock`
    // defaults to 0, so the `SameBlock` guard never fires for it. This test
    // documents the current (buggy) behavior; if the guard is ever wired
    // through `_update`, this test should start reverting and needs updating.
    function test_KNOWNGAP_sameBlockGuardBypassableViaTransfer() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(10e18, alice);

        // Same block: alice hands the shares to a fresh, never-deposited address.
        address freshHolder = makeAddr("freshHolder");
        vm.prank(alice);
        vault.transfer(freshHolder, shares);

        // Still the same block as the deposit — a direct redeem by alice would
        // revert with SameBlock, but freshHolder's guard was never stamped.
        vm.prank(freshHolder);
        uint256 assets = vault.redeem(shares, freshHolder, freshHolder);
        assertGt(assets, 0);
    }

    // ── Known gap: same-block DoS via attacker deposit-to-victim (SP-20) ─────────
    // PROPERTIES.md SP-20: `deposit`/`mint` unconditionally overwrite
    // `lastDepositBlock[receiver]`, even for a receiver who already holds
    // shares from a prior block. An attacker can deposit a small amount on
    // behalf of a victim to re-stamp the victim's guard and block their
    // same-block redemption of pre-existing shares (a 1-block griefing DoS,
    // not a fund-loss bug). This test documents the current behavior.
    function test_KNOWNGAP_sameBlockDosViaAttackerDepositToVictim() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(10e18, alice);
        vm.roll(block.number + 1);

        // Alice's guard was stamped in the previous block — a redeem here
        // would normally succeed.
        // Attacker (bob) grief-deposits a small amount ON BEHALF of alice,
        // re-stamping her lastDepositBlock in the current block.
        vm.prank(bob);
        vault.deposit(DEAD_SHARES + 1, alice);

        vm.prank(alice);
        vm.expectRevert(RebalancerVaultUpgradeable.SameBlock.selector);
        vault.redeem(shares, alice, alice);
    }

    // ── Full deposit -> redeem round trip never profits the caller (SP-01/02 style) ──

    function test_roundTrip_depositThenRedeemAll_neverProfits() public {
        _initialDeposit(10e18);

        uint256 balBefore = token0.balanceOf(bob);
        vm.prank(bob);
        vault.deposit(5e18, bob);
        vm.roll(block.number + 1);

        uint256 bobShares = vault.balanceOf(bob);
        vm.prank(bob);
        vault.redeem(bobShares, bob, bob);

        assertLe(token0.balanceOf(bob), balBefore);
    }

    function test_roundTrip_mintThenRedeem_neverProfits() public {
        _initialDeposit(10e18);

        uint256 balBefore = token0.balanceOf(bob);
        vm.prank(bob);
        uint256 shares = vault.mint(5e18, bob);
        vm.roll(block.number + 1);

        vm.prank(bob);
        vault.redeem(shares, bob, bob);

        assertLe(token0.balanceOf(bob), balBefore);
    }

    // ── deposit(assets, receiver) credits receiver, not msg.sender (SP-24) ───────

    function test_deposit_creditsReceiverNotSender() public {
        _initialDeposit(10e18);
        vm.prank(bob);
        uint256 shares = vault.deposit(5e18, carol);

        assertEq(vault.balanceOf(carol), shares);
        assertEq(vault.balanceOf(bob), 0);
    }

    // ── Dust deposit atomicity: 0-share deposit reverts without pulling tokens (SP-21) ──

    function test_dustDeposit_revertsAtomically_noTokensPulled() public {
        _initialDeposit(10e18);
        // Donate heavily so 1 wei of assets floors to 0 shares.
        vm.prank(owner);
        token0.transfer(address(vault), 1_000_000e18);

        uint256 aliceBalBefore = token0.balanceOf(alice);
        vm.prank(alice);
        vm.expectRevert(RebalancerVaultUpgradeable.ZeroAmount.selector);
        vault.deposit(1, alice);

        assertEq(token0.balanceOf(alice), aliceBalBefore);
    }
}
