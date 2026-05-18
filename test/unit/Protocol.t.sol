// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./BaseTest.t.sol";

contract BadRoundAggregator {
    uint8 private _decimals;

    constructor(uint8 dec) {
        _decimals = dec;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (2, 2000e8, block.timestamp, block.timestamp, 1);
    }
}

contract LendingPoolTest is BaseTest {
    function setUp() public override {
        super.setUp();
        _supplyDebt(bob, 40_000e18);
    }

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

    function test_borrow_basic() public {
        _depositCollateral(alice, 1e18);
        _borrow(alice, 1000e18);
        (, uint256 debt,,) = lending.positions(alice);
        assertEq(debt, 1000e18);
    }

    function test_borrow_reverts_exceedsLTV() public {
        _depositCollateral(alice, 1e18);
        vm.prank(alice);
        vm.expectRevert(LendingPool.ExceedsLTV.selector);
        lending.borrow(2000e18);
    }

    function test_borrow_reverts_noPosition() public {
        vm.prank(carol);
        vm.expectRevert(LendingPool.NoPosition.selector);
        lending.borrow(100e18);
    }

    function test_borrow_reverts_onZero() public {
        _depositCollateral(alice, 1e18);

        vm.prank(alice);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        lending.borrow(0);
    }

    function test_borrow_reverts_insufficientPoolLiquidity() public {
        _depositCollateral(bob, 100e18);
        vm.prank(bob);
        lending.borrow(1000e18);

        _depositCollateral(alice, 100e18);
        vm.prank(alice);
        vm.expectRevert(LendingPool.InsufficientPoolLiquidity.selector);
        lending.borrow(40_000e18);
    }

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
        lending.withdrawCollateral(1e18);
    }

    function test_withdrawCollateral_reverts_onZero() public {
        _depositCollateral(alice, 1e18);

        vm.prank(alice);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        lending.withdrawCollateral(0);
    }

    function test_withdrawCollateral_reverts_noPosition() public {
        vm.prank(carol);
        vm.expectRevert(LendingPool.NoPosition.selector);
        lending.withdrawCollateral(1e18);
    }

    function test_withdrawCollateral_reverts_tooMuch() public {
        _depositCollateral(alice, 1e18);

        vm.prank(alice);
        vm.expectRevert(LendingPool.InsufficientCollateral.selector);
        lending.withdrawCollateral(2e18);
    }

    function test_liquidate_successfulLiquidation() public {
        _depositCollateral(alice, 1e18);
        _borrow(alice, 1400e18);

        vm.prank(admin);
        feedA.setAnswer(1500e8);

        uint256 colBefore = tokenA.balanceOf(carol);

        vm.prank(carol);
        lending.liquidate(alice, 700e18);

        assertGt(tokenA.balanceOf(carol), colBefore);
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

    function test_liquidate_reverts_onZeroRepay() public {
        vm.prank(carol);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        lending.liquidate(alice, 0);
    }

    function test_interestAccrues_overTime() public {
        _depositCollateral(alice, 1e18);
        _borrow(alice, 500e18);

        uint256 debtBefore = lending.currentDebt(alice);

        vm.warp(block.timestamp + 365 days);
        lending.accrueInterest();

        uint256 debtAfter = lending.currentDebt(alice);
        assertGt(debtAfter, debtBefore);
    }

    function test_oracle_stalePriceReverts() public {
        _depositCollateral(alice, 1e18);

        vm.warp(block.timestamp + 7200);

        vm.prank(alice);
        vm.expectRevert();
        lending.borrow(100e18);
    }

    function test_supplyDebtToken_basic() public {
        tokenB.mint(carol, 1000e18);

        vm.startPrank(carol);
        tokenB.approve(address(lending), 1000e18);
        lending.supplyDebtToken(1000e18);
        vm.stopPrank();

        assertEq(tokenB.balanceOf(address(lending)), 41_000e18);
    }

    function test_supplyDebtToken_reverts_onZero() public {
        vm.prank(carol);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        lending.supplyDebtToken(0);
    }

    function test_utilizationRate_zeroDebt() public view {
        assertEq(lending.utilizationRate(), 0);
    }

    function test_utilizationRate_afterBorrow() public {
        _depositCollateral(alice, 1e18);
        _borrow(alice, 500e18);

        assertGt(lending.utilizationRate(), 0);
    }

    function test_healthFactor_noDebt_returnsMax() public {
        _depositCollateral(alice, 1e18);

        assertEq(lending.healthFactor(alice), type(uint256).max);
    }

    function test_currentDebt_noPosition_isZero() public view {
        assertEq(lending.currentDebt(carol), 0);
    }

    function test_pause_onlyPauser() public {
        vm.prank(alice);
        vm.expectRevert();
        lending.pause();
    }

    function test_pause_blocksDeposit() public {
        vm.prank(admin);
        lending.pause();

        vm.prank(alice);
        vm.expectRevert();
        lending.depositCollateral(1e18);
    }

    function test_unpause_restoresDeposit() public {
        vm.prank(admin);
        lending.pause();

        vm.prank(admin);
        lending.unpause();

        vm.prank(alice);
        lending.depositCollateral(1e18);

        (uint256 coll,,, LendingPool.PositionState state) = lending.positions(alice);
        assertEq(coll, 1e18);
        assertEq(uint256(state), uint256(LendingPool.PositionState.Active));
    }

    function test_unpause_onlyPauser() public {
        vm.prank(admin);
        lending.pause();

        vm.prank(alice);
        vm.expectRevert();
        lending.unpause();
    }

    function test_withdrawReserves_reverts_invalidAmount() public {
        vm.prank(admin);
        vm.expectRevert(LendingPool.InvalidAmount.selector);
        lending.withdrawReserves(1);
    }

    function test_withdrawReserves_onlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        lending.withdrawReserves(0);
    }

    function test_withdrawReserves_success() public {
        _depositCollateral(alice, 1e18);
        _borrow(alice, 1000e18);

        vm.warp(block.timestamp + 365 days);
        lending.accrueInterest();

        uint256 reserves = lending.totalReserves();
        assertGt(reserves, 0);

        uint256 treasuryBefore = tokenB.balanceOf(address(treasury));

        vm.prank(admin);
        lending.withdrawReserves(reserves);

        assertEq(lending.totalReserves(), 0);
        assertEq(tokenB.balanceOf(address(treasury)), treasuryBefore + reserves);
    }
}

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

    function test_mint_reverts_onZero() public {
        vm.prank(alice);
        vm.expectRevert(YieldVault.ZeroAmount.selector);
        vault.mint(0, alice);
    }

    function test_withdraw_reverts_onZero() public {
        vm.prank(alice);
        vm.expectRevert(YieldVault.ZeroAmount.selector);
        vault.withdraw(0, alice, alice);
    }

    function test_redeem_reverts_onZero() public {
        vm.prank(alice);
        vm.expectRevert(YieldVault.ZeroAmount.selector);
        vault.redeem(0, alice, alice);
    }

    function test_erc4626_roundingInvariant_deposit() public view {
        uint256 assets = 1000e18;
        uint256 shares = vault.previewDeposit(assets);
        uint256 actual = vault.convertToShares(assets);

        assertLe(shares, actual + 1);
    }

    function test_erc4626_roundingInvariant_redeem() public view {
        uint256 shares = 1000e18;
        uint256 preview = vault.previewRedeem(shares);
        uint256 actual = vault.convertToAssets(shares);

        assertLe(preview, actual + 1);
    }

    function test_vault_pausable() public {
        vm.prank(admin);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(100e18, alice);
    }

    function test_unpause_allowsDeposit() public {
        vm.prank(admin);
        vault.pause();

        vm.prank(admin);
        vault.unpause();

        vm.prank(alice);
        uint256 shares = vault.deposit(100e18, alice);

        assertGt(shares, 0);
    }

    function test_pause_onlyPauser() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.pause();
    }

    function test_unpause_onlyPauser() public {
        vm.prank(admin);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert();
        vault.unpause();
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

    function test_setFeeRecipient_success() public {
        vm.prank(admin);
        vault.setFeeRecipient(carol);

        assertEq(vault.feeRecipient(), carol);
    }

    function test_setFeeRecipient_reverts_zeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(YieldVault.ZeroAddress.selector);
        vault.setFeeRecipient(address(0));
    }

    function test_setFeeRecipient_onlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setFeeRecipient(carol);
    }

    function test_harvestYield_reverts_onZero() public {
        vm.prank(keeper);
        vm.expectRevert(YieldVault.ZeroAmount.selector);
        vault.harvestYield(0);
    }

    function test_harvestYield_withFeeTransfersFee() public {
        vm.prank(admin);
        vault.setPerformanceFee(1000);

        vm.prank(admin);
        vault.setFeeRecipient(carol);

        tokenB.mint(keeper, 100e18);

        uint256 carolBefore = tokenB.balanceOf(carol);

        vm.startPrank(keeper);
        tokenB.approve(address(vault), 100e18);
        vault.harvestYield(100e18);
        vm.stopPrank();

        assertEq(tokenB.balanceOf(carol), carolBefore + 10e18);
        assertEq(vault.totalHarvested(), 90e18);
    }
}

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

    function test_v2_init_reverts_ifCalledTwice() public {
        GovernanceTokenV2 implV2 = new GovernanceTokenV2();

        vm.prank(admin);
        govToken.upgradeToAndCall(address(implV2), "");

        GovernanceTokenV2 v2 = GovernanceTokenV2(address(govToken));

        vm.prank(admin);
        v2.initV2(100);

        vm.prank(admin);
        vm.expectRevert(GovernanceTokenV2.AlreadyInitializedV2.selector);
        v2.initV2(200);
    }

    function test_v2_init_onlyUpgrader() public {
        GovernanceTokenV2 implV2 = new GovernanceTokenV2();

        vm.prank(admin);
        govToken.upgradeToAndCall(address(implV2), "");

        GovernanceTokenV2 v2 = GovernanceTokenV2(address(govToken));

        vm.prank(alice);
        vm.expectRevert();
        v2.initV2(100);
    }

    function test_v2_setStakingRewardRate_admin() public {
        GovernanceTokenV2 implV2 = new GovernanceTokenV2();

        vm.prank(admin);
        govToken.upgradeToAndCall(address(implV2), "");

        GovernanceTokenV2 v2 = GovernanceTokenV2(address(govToken));

        vm.prank(admin);
        v2.initV2(100);

        vm.prank(admin);
        v2.setStakingRewardRate(250);

        assertEq(v2.stakingRewardRate(), 250);
    }

    function test_v2_setStakingRewardRate_onlyAdmin() public {
        GovernanceTokenV2 implV2 = new GovernanceTokenV2();

        vm.prank(admin);
        govToken.upgradeToAndCall(address(implV2), "");

        GovernanceTokenV2 v2 = GovernanceTokenV2(address(govToken));

        vm.prank(admin);
        v2.initV2(100);

        vm.prank(alice);
        vm.expectRevert();
        v2.setStakingRewardRate(250);
    }
}

contract OracleTest is BaseTest {
    function test_getPrice_basic() public view {
        uint256 price = oracle.getPrice(address(tokenA));
        assertEq(price, 2000e18);
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

    function test_constructor_reverts_zeroAdmin() public {
        vm.expectRevert(ChainlinkOracle.ZeroAddress.selector);
        new ChainlinkOracle(address(0));
    }

    function test_setFeed_reverts_zeroToken() public {
        vm.prank(admin);
        vm.expectRevert(ChainlinkOracle.ZeroAddress.selector);
        oracle.setFeed(address(0), address(feedA), 3600);
    }

    function test_setFeed_reverts_zeroFeed() public {
        vm.prank(admin);
        vm.expectRevert(ChainlinkOracle.ZeroAddress.selector);
        oracle.setFeed(address(tokenA), address(0), 3600);
    }

    function test_getFeedConfig_returnsValues() public view {
        (address feed, uint32 maxStaleness, uint8 dec) = oracle.getFeedConfig(address(tokenA));

        assertEq(feed, address(feedA));
        assertEq(maxStaleness, 3600);
        assertEq(dec, 8);
    }

    function test_getPrice_decimals18() public {
        MockAggregator feed18 = new MockAggregator(18, 2000e18);

        vm.prank(admin);
        oracle.setFeed(address(tokenC), address(feed18), 3600);

        uint256 price = oracle.getPrice(address(tokenC));

        assertEq(price, 2000e18);
    }

    function test_getPrice_decimalsGreaterThan18() public {
        MockAggregator feed20 = new MockAggregator(20, 200000e20);

        vm.prank(admin);
        oracle.setFeed(address(tokenC), address(feed20), 3600);

        uint256 price = oracle.getPrice(address(tokenC));

        assertEq(price, 200000e18);
    }

    function test_getPrice_reverts_zeroPriceAfterScaling() public {
        MockAggregator feed20 = new MockAggregator(20, 1);

        vm.prank(admin);
        oracle.setFeed(address(tokenC), address(feed20), 3600);

        vm.expectRevert(abi.encodeWithSelector(ChainlinkOracle.ZeroPrice.selector, address(tokenC)));
        oracle.getPrice(address(tokenC));
    }

    function test_getPrice_reverts_invalidRound() public {
        BadRoundAggregator badFeed = new BadRoundAggregator(8);

        vm.prank(admin);
        oracle.setFeed(address(tokenC), address(badFeed), 3600);

        vm.expectRevert(ChainlinkOracle.InvalidRound.selector);
        oracle.getPrice(address(tokenC));
    }

    function test_mockAggregator_helpers() public {
        vm.warp(1000);

        feedA.setUpdatedAt(block.timestamp - 100);
        feedA.setRoundId(10);
        feedA.setAnswer(2500e8);

        uint256 price = oracle.getPrice(address(tokenA));

        assertEq(price, 2500e18);
    }
}

contract TreasuryTest is BaseTest {
    function test_receiveEther() public {
        vm.deal(alice, 1 ether);

        vm.prank(alice);
        (bool ok,) = address(treasury).call{ value: 1 ether }("");

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
        vm.deal(address(treasury), 1 ether);

        vm.prank(address(timelock));
        vm.expectRevert(Treasury.TransferFailed.selector);
        treasury.withdrawEther(payable(address(this)), 1 ether);
    }

    function test_constructor_reverts_zeroAdmin() public {
        vm.expectRevert(Treasury.ZeroAddress.selector);
        new Treasury(address(0));
    }

    function test_withdrawEther_success() public {
        vm.deal(address(treasury), 2 ether);

        uint256 carolBefore = carol.balance;

        vm.prank(address(timelock));
        treasury.withdrawEther(payable(carol), 1 ether);

        assertEq(carol.balance, carolBefore + 1 ether);
        assertEq(treasury.ethBalance(), 1 ether);
    }

    function test_withdrawEther_reverts_zeroAddress() public {
        vm.deal(address(treasury), 1 ether);

        vm.prank(address(timelock));
        vm.expectRevert(Treasury.ZeroAddress.selector);
        treasury.withdrawEther(payable(address(0)), 1 ether);
    }

    function test_withdrawEther_reverts_zeroAmount() public {
        vm.deal(address(treasury), 1 ether);

        vm.prank(address(timelock));
        vm.expectRevert(Treasury.ZeroAmount.selector);
        treasury.withdrawEther(payable(carol), 0);
    }

    function test_withdrawToken_success() public {
        tokenB.mint(address(treasury), 1000e18);

        uint256 carolBefore = tokenB.balanceOf(carol);

        vm.prank(address(timelock));
        treasury.withdrawToken(address(tokenB), carol, 500e18);

        assertEq(tokenB.balanceOf(carol), carolBefore + 500e18);
        assertEq(treasury.tokenBalance(address(tokenB)), 500e18);
    }

    function test_withdrawToken_reverts_zeroToken() public {
        vm.prank(address(timelock));
        vm.expectRevert(Treasury.ZeroAddress.selector);
        treasury.withdrawToken(address(0), carol, 100e18);
    }

    function test_withdrawToken_reverts_zeroRecipient() public {
        tokenB.mint(address(treasury), 1000e18);

        vm.prank(address(timelock));
        vm.expectRevert(Treasury.ZeroAddress.selector);
        treasury.withdrawToken(address(tokenB), address(0), 100e18);
    }

    function test_withdrawToken_reverts_zeroAmount() public {
        tokenB.mint(address(treasury), 1000e18);

        vm.prank(address(timelock));
        vm.expectRevert(Treasury.ZeroAmount.selector);
        treasury.withdrawToken(address(tokenB), carol, 0);
    }

    receive() external payable {
        revert("no");
    }
}
