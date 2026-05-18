// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./BaseTest.t.sol";

contract LendingPoolTest is BaseTest {
    function setUp() public override {
        super.setUp();
        // Seed pool with debt liquidity
        _supplyDebt(bob, 40_000e18);
    }

    // ── Deposit Collateral ──────────────────────────────────────────────────
    function test_depositCollateral_basic() public {
        _depositCollateral(alice, 1000e18);
        (uint256 coll,,, LendingPool.PositionState state) = lending.positions(alice);
        assertEq(coll, 1000e18);
        assertEq(uint256(state), uint256(LendingPool.PositionState.Active));
    }

    function test_depositCollateral_reverts_onZero() public {
        vm.prank(alice);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        lending.depositCollateral(0);
    }

    function test_depositCollateral_updatesTotalCollateral() public {
        _depositCollateral(alice, 5000e18);
        assertEq(lending.totalCollateral(), 5000e18);
    }

    // ── Borrow ──────────────────────────────────────────────────────────────
    function test_borrow_basic() public {
        _depositCollateral(alice, 1e18); // 1 tokenA = $2000
        // LTV 75 %, $2000 * 0.75 = $1500, tokenB = $1, so max borrow = 1500
        _borrow(alice, 1000e18);
        (, uint256 debt,,) = lending.positions(alice);
        assertEq(debt, 1000e18);
    }

    function test_borrow_reverts_exceedsLTV() public {
        _depositCollateral(alice, 1e18); // $2000 collateral
        vm.prank(alice);
        vm.expectRevert(LendingPool.ExceedsLTV.selector);
        lending.borrow(2000e18); // would breach 80 % liq threshold
    }

    function test_borrow_reverts_noPosition() public {
        vm.prank(carol);
        vm.expectRevert(LendingPool.NoPosition.selector);
        lending.borrow(100e18);
    }

    function test_borrow_reverts_insufficientPoolLiquidity() public {
        // Drain the pool first (use bob's position to borrow almost everything)
        _depositCollateral(bob, 100e18);
        vm.prank(bob);
        lending.borrow(1000e18); // $200,000 collateral, $1000 borrow - within LTV? Let's just take whatever

        _depositCollateral(alice, 100e18);
        vm.prank(alice);
        vm.expectRevert(LendingPool.InsufficientPoolLiquidity.selector);
        lending.borrow(40_000e18); // more than pool has
    }

    // ── Repay ────────────────────────────────────────────────────────────────
    function test_repay_clearsDebt() public {
        _depositCollateral(alice, 1e18);
        _borrow(alice, 500e18);

        vm.prank(alice);
        lending.repay(500e18);
        (, uint256 debt,,) = lending.positions(alice);
        assertEq(debt, 0);
    }

    function test_repay_reverts_noPosition() public {
        vm.prank(carol);
        vm.expectRevert(LendingPool.NoPosition.selector);
        lending.repay(100e18);
    }

    function test_repay_reverts_onZero() public {
        _depositCollateral(alice, 1e18);
        vm.prank(alice);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        lending.repay(0);
    }

    // ── Withdraw Collateral ─────────────────────────────────────────────────
    function test_withdrawCollateral_afterRepay() public {
        _depositCollateral(alice, 1e18);
        _borrow(alice, 500e18);

        vm.prank(alice);
        lending.repay(500e18);

        uint256 balBefore = tokenA.balanceOf(alice);
        vm.prank(alice);
        lending.withdrawCollateral(1e18);
        assertEq(tokenA.balanceOf(alice), balBefore + 1e18);
    }

    function test_withdrawCollateral_reverts_breachesHealth() public {
        _depositCollateral(alice, 1e18);
        _borrow(alice, 1000e18);

        vm.prank(alice);
        vm.expectRevert(LendingPool.InsufficientCollateral.selector);
        lending.withdrawCollateral(1e18); // would drop health factor < 1
    }

    // ── Liquidation ─────────────────────────────────────────────────────────
    function test_liquidate_successfulLiquidation() public {
        _depositCollateral(alice, 1e18); // $2000 col
        _borrow(alice, 1400e18);         // $1400 debt → HF = 2000*0.8/1400 ≈ 1.14 (healthy)

        // Drop tokenA price so position becomes underwater
        vm.prank(admin);
        feedA.setAnswer(1500e8); // tokenA now $1500, HF = 1500*0.8/1400 ≈ 0.857

        uint256 colBefore = tokenA.balanceOf(carol);
        vm.prank(carol);
        lending.liquidate(alice, 700e18); // 50 % close factor

        assertGt(tokenA.balanceOf(carol), colBefore); // carol received collateral
    }

    function test_liquidate_reverts_healthyPosition() public {
        _depositCollateral(alice, 1e18);
        _borrow(alice, 1000e18);

        vm.prank(carol);
        vm.expectRevert(LendingPool.HealthyPosition.selector);
        lending.liquidate(alice, 500e18);
    }

    function test_liquidate_reverts_noPosition() public {
        vm.prank(carol);
        vm.expectRevert(LendingPool.NoPosition.selector);
        lending.liquidate(alice, 100e18);
    }

    // ── Interest ─────────────────────────────────────────────────────────────
    function test_interestAccrues_overTime() public {
        _depositCollateral(alice, 1e18);
        _borrow(alice, 500e18);
        uint256 debtBefore = lending.currentDebt(alice);

        vm.warp(block.timestamp + 365 days);
        lending.accrueInterest();
        uint256 debtAfter = lending.currentDebt(alice);
        assertGt(debtAfter, debtBefore);
    }

    // ── Oracle ───────────────────────────────────────────────────────────────
    function test_oracle_stalePriceReverts() public {
        vm.warp(block.timestamp + 7200); // > 3600s staleness
        vm.prank(alice);
        vm.expectRevert();
        lending.depositCollateral(1e18); // oracle call inside accrueInterest path
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// YieldVault tests
// ─────────────────────────────────────────────────────────────────────────────
contract YieldVaultTest is BaseTest {
    function test_deposit_mintSharesProperly() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(1000e18, alice);
        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalAssets(), 1000e18);
    }

    function test_withdraw_returnsAssets() public {
        vm.prank(alice);
        vault.deposit(1000e18, alice);

        uint256 balBefore = tokenB.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(900e18, alice, alice);
        assertApproxEqAbs(tokenB.balanceOf(alice), balBefore + 900e18, 1e6);
    }

    function test_redeem_burnsShares() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(1000e18, alice);

        vm.prank(alice);
        vault.redeem(shares, alice, alice);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_harvestYield_increasesSharePrice() public {
        vm.prank(alice);
        vault.deposit(1000e18, alice);
        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 assetsBefore = vault.convertToAssets(sharesBefore);

        // keeper harvests yield
        vm.prank(keeper);
        vault.harvestYield(100e18);

        uint256 assetsAfter = vault.convertToAssets(sharesBefore);
        assertGt(assetsAfter, assetsBefore);
    }

    function test_harvestYield_onlyKeeper() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.harvestYield(100e18);
    }

    function test_deposit_reverts_onZero() public {
        vm.prank(alice);
        vm.expectRevert(YieldVault.ZeroAmount.selector);
        vault.deposit(0, alice);
    }

    function test_erc4626_roundingInvariant_deposit() public view {
        uint256 assets = 1000e18;
        uint256 shares = vault.previewDeposit(assets);
        uint256 actual = vault.convertToShares(assets);
        // previewDeposit should be <= convertToShares (round down for shares)
        assertLe(shares, actual + 1); // within 1 wei
    }

    function test_erc4626_roundingInvariant_redeem() public view {
        uint256 shares = 1000e18;
        uint256 preview = vault.previewRedeem(shares);
        uint256 actual  = vault.convertToAssets(shares);
        assertLe(preview, actual + 1);
    }

    function test_vault_pausable() public {
        vm.prank(admin);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(100e18, alice);
    }

    function test_setPerformanceFee_onlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setPerformanceFee(500);
    }

    function test_setPerformanceFee_tooHigh_reverts() public {
        vm.prank(admin);
        vm.expectRevert(YieldVault.FeeTooHigh.selector);
        vault.setPerformanceFee(3001);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// GovernanceToken tests
// ─────────────────────────────────────────────────────────────────────────────
contract GovernanceTokenTest is BaseTest {
    function test_mint_onlyMinter() public {
        vm.prank(alice);
        vm.expectRevert();
        govToken.mint(alice, 1000e18);
    }

    function test_mint_exceedsMaxSupply_reverts() public {
        vm.prank(admin);
        vm.expectRevert();
        govToken.mint(alice, 100_000_001e18);
    }

    function test_mint_and_burn() public {
        vm.prank(admin);
        govToken.mint(alice, 1000e18);
        assertEq(govToken.balanceOf(alice), 1000e18);

        vm.prank(alice);
        govToken.burn(500e18);
        assertEq(govToken.balanceOf(alice), 500e18);
    }

    function test_votingPower_afterDelegate() public {
        vm.prank(admin);
        govToken.mint(alice, 1000e18);

        vm.prank(alice);
        govToken.delegate(alice);

        assertEq(govToken.getVotes(alice), 1000e18);
    }

    function test_uups_upgradeToV2() public {
        GovernanceTokenV2 implV2 = new GovernanceTokenV2();
        vm.prank(admin);
        govToken.upgradeToAndCall(address(implV2), "");

        // Cast and verify V2 functionality
        GovernanceTokenV2 v2 = GovernanceTokenV2(address(govToken));
        vm.prank(admin);
        v2.initV2(100);
        assertEq(v2.stakingRewardRate(), 100);
    }

    function test_uups_upgrade_onlyUpgrader() public {
        GovernanceTokenV2 implV2 = new GovernanceTokenV2();
        vm.prank(alice);
        vm.expectRevert();
        govToken.upgradeToAndCall(address(implV2), "");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Oracle tests
// ─────────────────────────────────────────────────────────────────────────────
contract OracleTest is BaseTest {
    function test_getPrice_basic() public view {
        uint256 price = oracle.getPrice(address(tokenA));
        assertEq(price, 2000e18); // $2000 normalised to 18 decimals
    }

    function test_getPrice_reverts_onStaleFeed() public {
        vm.warp(block.timestamp + 3601);
        vm.expectRevert();
        oracle.getPrice(address(tokenA));
    }

    function test_getPrice_reverts_onNegativePrice() public {
        vm.prank(admin);
        feedA.setAnswer(-1);
        vm.expectRevert();
        oracle.getPrice(address(tokenA));
    }

    function test_getPrice_reverts_onFeedNotSet() public {
        address unknown = makeAddr("unknown");
        vm.expectRevert(abi.encodeWithSelector(ChainlinkOracle.FeedNotSet.selector, unknown));
        oracle.getPrice(unknown);
    }

    function test_setFeed_onlyOracleAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        oracle.setFeed(address(tokenC), address(feedA), 3600);
    }

    function test_removeFeed() public {
        vm.prank(admin);
        oracle.removeFeed(address(tokenA));
        vm.expectRevert();
        oracle.getPrice(address(tokenA));
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Treasury tests
// ─────────────────────────────────────────────────────────────────────────────
contract TreasuryTest is BaseTest {
    function test_receiveEther() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(treasury).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(treasury.ethBalance(), 1 ether);
    }

    function test_withdrawToken_onlyTreasurer() public {
        tokenB.mint(address(treasury), 1000e18);
        vm.prank(alice);
        vm.expectRevert();
        treasury.withdrawToken(address(tokenB), alice, 1000e18);
    }

    function test_withdrawEther_transferFailed_reverts() public {
        // Deploy a contract that rejects ETH
        vm.deal(address(treasury), 1 ether);
        vm.prank(address(timelock));
        vm.expectRevert(Treasury.TransferFailed.selector);
        treasury.withdrawEther(payable(address(this)), 1 ether);
    }

    // This contract rejects ETH
    receive() external payable { revert("no"); }
}
