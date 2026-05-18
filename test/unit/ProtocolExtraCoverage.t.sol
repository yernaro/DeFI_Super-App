// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./BaseTest.t.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/governance/IGovernor.sol";

contract GovernanceTokenExtraCoverageTest is BaseTest {
    function test_initialize_reverts_zeroAdmin() public {
        GovernanceToken impl = new GovernanceToken();

        bytes memory data = abi.encodeCall(GovernanceToken.initialize, (address(0), admin, 100_000_000e18));

        vm.expectRevert(GovernanceToken.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function test_initialize_reverts_zeroMinter() public {
        GovernanceToken impl = new GovernanceToken();

        bytes memory data = abi.encodeCall(GovernanceToken.initialize, (admin, address(0), 100_000_000e18));

        vm.expectRevert(GovernanceToken.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function test_mint_reverts_zeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(GovernanceToken.ZeroAddress.selector);
        govToken.mint(address(0), 100e18);
    }

    function test_mint_reverts_zeroAmount() public {
        vm.prank(admin);
        vm.expectRevert(GovernanceToken.ZeroAmount.selector);
        govToken.mint(alice, 0);
    }

    function test_burn_reverts_zeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(GovernanceToken.ZeroAmount.selector);
        govToken.burn(0);
    }

    function test_transfer_updatesVotesAndBalances() public {
        vm.prank(admin);
        govToken.mint(alice, 1000e18);

        vm.prank(alice);
        govToken.delegate(alice);

        vm.roll(block.number + 1);

        assertEq(govToken.getVotes(alice), 1000e18);

        vm.prank(alice);
        govToken.transfer(bob, 400e18);

        assertEq(govToken.balanceOf(alice), 600e18);
        assertEq(govToken.balanceOf(bob), 400e18);
    }

    function test_nonces_initialValue() public view {
        assertEq(govToken.nonces(alice), 0);
    }
}

contract DeFiGovernorExtraCoverageTest is BaseTest {
    uint256 constant PROPOSER_AMOUNT = 1_500_000e18;

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        govToken.mint(alice, PROPOSER_AMOUNT);
        govToken.mint(bob, 40_000_000e18);
        vm.stopPrank();

        vm.prank(alice);
        govToken.delegate(alice);

        vm.prank(bob);
        govToken.delegate(bob);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 13);
    }

    function test_governor_viewFunctions() public view {
        assertEq(governor.name(), "DeFiSuperApp Governor");
        assertEq(governor.votingDelay(), 1 days);
        assertEq(governor.votingPeriod(), 1 weeks);
        assertEq(governor.quorumNumerator(), 4);
        assertEq(governor.proposalThreshold(), govToken.getPastTotalSupply(block.number - 1) / 100);
        assertTrue(governor.supportsInterface(type(IGovernor).interfaceId));
    }

    function test_governor_proposalNeedsQueuing_afterSuccess() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(treasury);
        values[0] = 0;
        calldatas[0] = "";

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Needs queue coverage");

        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(bob);
        governor.castVote(proposalId, 1);

        vm.roll(governor.proposalDeadline(proposalId) + 1);
        vm.warp(block.timestamp + 1 weeks + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));
        assertTrue(governor.proposalNeedsQueuing(proposalId));
    }

    function test_governor_quorumAtPastBlock() public view {
        uint256 pastBlock = block.number - 1;
        uint256 expected = govToken.getPastTotalSupply(pastBlock) * 4 / 100;

        assertEq(governor.quorum(pastBlock), expected);
    }
}

contract YieldVaultAdditionalCoverageTest is BaseTest {
    function test_yieldVault_initialize_success_directProxy() public {
        YieldVault impl = new YieldVault();

        bytes memory data =
            abi.encodeCall(YieldVault.initialize, (address(tokenB), "Vault", "vTOKEN", 1000, admin, admin));

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        YieldVault initializedVault = YieldVault(address(proxy));

        assertEq(initializedVault.name(), "Vault");
        assertEq(initializedVault.symbol(), "vTOKEN");
        assertEq(initializedVault.asset(), address(tokenB));
        assertEq(initializedVault.performanceFee(), 1000);
        assertEq(initializedVault.feeRecipient(), admin);
        assertTrue(initializedVault.hasRole(initializedVault.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(initializedVault.hasRole(initializedVault.KEEPER_ROLE(), admin));
        assertTrue(initializedVault.hasRole(initializedVault.PAUSER_ROLE(), admin));
        assertTrue(initializedVault.hasRole(initializedVault.UPGRADER_ROLE(), admin));
    }

    function test_yieldVault_initialize_reverts_zeroAsset() public {
        YieldVault impl = new YieldVault();

        bytes memory data = abi.encodeCall(YieldVault.initialize, (address(0), "Vault", "vTOKEN", 1000, admin, admin));

        vm.expectRevert(YieldVault.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function test_yieldVault_initialize_reverts_zeroFeeRecipient() public {
        YieldVault impl = new YieldVault();

        bytes memory data =
            abi.encodeCall(YieldVault.initialize, (address(tokenB), "Vault", "vTOKEN", 1000, address(0), admin));

        vm.expectRevert(YieldVault.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function test_yieldVault_initialize_reverts_zeroAdmin() public {
        YieldVault impl = new YieldVault();

        bytes memory data =
            abi.encodeCall(YieldVault.initialize, (address(tokenB), "Vault", "vTOKEN", 1000, admin, address(0)));

        vm.expectRevert(YieldVault.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function test_yieldVault_initialize_reverts_feeTooHigh() public {
        YieldVault impl = new YieldVault();

        bytes memory data =
            abi.encodeCall(YieldVault.initialize, (address(tokenB), "Vault", "vTOKEN", 3001, admin, admin));

        vm.expectRevert(YieldVault.FeeTooHigh.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function test_yieldVault_setPerformanceFee_success() public {
        vm.prank(admin);
        vault.setPerformanceFee(250);

        assertEq(vault.performanceFee(), 250);
    }

    function test_yieldVault_pause_unpause_directCoverage() public {
        vm.prank(admin);
        vault.pause();

        vm.prank(admin);
        vault.unpause();

        assertFalse(vault.paused());
    }
}

contract LendingPoolAdditionalCoverageTest is BaseTest {
    function test_lendingPool_initialize_success_directProxy() public {
        LendingPool impl = new LendingPool();

        bytes memory data = abi.encodeCall(
            LendingPool.initialize, (address(tokenA), address(tokenB), address(oracle), address(treasury), admin)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        LendingPool initializedLending = LendingPool(address(proxy));

        assertEq(address(initializedLending.collateralToken()), address(tokenA));
        assertEq(address(initializedLending.debtToken()), address(tokenB));
        assertEq(address(initializedLending.oracle()), address(oracle));
        assertEq(initializedLending.treasury(), address(treasury));
        assertEq(initializedLending.cumulativeInterestIndex(), 1e27);
        assertEq(initializedLending.lastAccrualTimestamp(), block.timestamp);
        assertTrue(initializedLending.hasRole(initializedLending.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(initializedLending.hasRole(initializedLending.PAUSER_ROLE(), admin));
        assertTrue(initializedLending.hasRole(initializedLending.UPGRADER_ROLE(), admin));
        assertTrue(initializedLending.hasRole(initializedLending.RISK_ADMIN(), admin));
    }

    function test_lendingPool_initialize_reverts_zeroCollateralToken() public {
        LendingPool impl = new LendingPool();

        bytes memory data = abi.encodeCall(
            LendingPool.initialize, (address(0), address(tokenB), address(oracle), address(treasury), admin)
        );

        vm.expectRevert(LendingPool.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function test_lendingPool_initialize_reverts_zeroDebtToken() public {
        LendingPool impl = new LendingPool();

        bytes memory data = abi.encodeCall(
            LendingPool.initialize, (address(tokenA), address(0), address(oracle), address(treasury), admin)
        );

        vm.expectRevert(LendingPool.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function test_lendingPool_initialize_reverts_zeroOracle() public {
        LendingPool impl = new LendingPool();

        bytes memory data = abi.encodeCall(
            LendingPool.initialize, (address(tokenA), address(tokenB), address(0), address(treasury), admin)
        );

        vm.expectRevert(LendingPool.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function test_lendingPool_initialize_reverts_zeroTreasury() public {
        LendingPool impl = new LendingPool();

        bytes memory data = abi.encodeCall(
            LendingPool.initialize, (address(tokenA), address(tokenB), address(oracle), address(0), admin)
        );

        vm.expectRevert(LendingPool.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function test_lendingPool_initialize_reverts_zeroAdmin() public {
        LendingPool impl = new LendingPool();

        bytes memory data = abi.encodeCall(
            LendingPool.initialize, (address(tokenA), address(tokenB), address(oracle), address(treasury), address(0))
        );

        vm.expectRevert(LendingPool.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function test_lendingPool_accrueInterest_sameTimestamp_returnsEarly() public {
        uint256 lastAccrual = lending.lastAccrualTimestamp();

        lending.accrueInterest();

        assertEq(lending.lastAccrualTimestamp(), lastAccrual);
        assertEq(lending.totalDebt(), 0);
    }

    function test_lendingPool_accrueInterest_zeroInterest_updatesTimestamp() public {
        _supplyDebt(bob, 100e18);
        _depositCollateral(alice, 1e18);
        _borrow(alice, 1);

        vm.warp(block.timestamp + 1);
        uint256 expectedTimestamp = block.timestamp;

        lending.accrueInterest();

        assertEq(lending.lastAccrualTimestamp(), expectedTimestamp);
        assertEq(lending.totalDebt(), 1);
    }

    function test_lendingPool_withdrawCollateral_withoutDebt() public {
        _depositCollateral(alice, 2e18);

        uint256 aliceBefore = tokenA.balanceOf(alice);

        vm.prank(alice);
        lending.withdrawCollateral(1e18);

        (uint256 collateral,,, LendingPool.PositionState state) = lending.positions(alice);
        assertEq(collateral, 1e18);
        assertEq(lending.totalCollateral(), 1e18);
        assertEq(tokenA.balanceOf(alice), aliceBefore + 1e18);
        assertEq(uint256(state), uint256(LendingPool.PositionState.Active));
    }

    function test_lendingPool_repay_capsToCurrentDebt() public {
        _supplyDebt(bob, 40_000e18);
        _depositCollateral(alice, 1e18);
        _borrow(alice, 500e18);

        vm.prank(alice);
        lending.repay(1000e18);

        (, uint256 debt,,) = lending.positions(alice);
        assertEq(debt, 0);
        assertEq(lending.totalDebt(), 0);
    }

    function test_lendingPool_liquidate_capsRepayToHalfDebt() public {
        _supplyDebt(bob, 40_000e18);
        _depositCollateral(alice, 1e18);
        _borrow(alice, 1400e18);

        vm.prank(admin);
        feedA.setAnswer(1500e8);

        vm.prank(carol);
        lending.liquidate(alice, 10_000e18);

        (, uint256 debt,, LendingPool.PositionState state) = lending.positions(alice);
        assertEq(debt, 700e18);
        assertEq(uint256(state), uint256(LendingPool.PositionState.Active));
    }

    function test_lendingPool_liquidate_capsCollateralAndMarksLiquidated() public {
        _supplyDebt(bob, 100e18);
        _depositCollateral(alice, 1e8);
        _borrow(alice, 1);

        vm.prank(admin);
        feedA.setAnswer(1);

        vm.prank(carol);
        lending.liquidate(alice, 1);

        (uint256 collateral, uint256 debt,, LendingPool.PositionState state) = lending.positions(alice);
        assertEq(collateral, 0);
        assertEq(debt, 0);
        assertEq(uint256(state), uint256(LendingPool.PositionState.Liquidated));
    }
}

contract UpgradeAuthorizationAdditionalTest is BaseTest {
    function test_yieldVault_upgrade_onlyUpgrader() public {
        YieldVault newImpl = new YieldVault();

        vm.prank(alice);
        vm.expectRevert();
        vault.upgradeToAndCall(address(newImpl), "");
    }

    function test_yieldVault_upgrade_byAdmin() public {
        YieldVault newImpl = new YieldVault();

        vm.prank(admin);
        vault.upgradeToAndCall(address(newImpl), "");
    }

    function test_lendingPool_upgrade_onlyUpgrader() public {
        LendingPool newImpl = new LendingPool();

        vm.prank(alice);
        vm.expectRevert();
        lending.upgradeToAndCall(address(newImpl), "");
    }

    function test_lendingPool_upgrade_byAdmin() public {
        LendingPool newImpl = new LendingPool();

        vm.prank(admin);
        lending.upgradeToAndCall(address(newImpl), "");
    }
}

contract GovernorCancelAdditionalTest is BaseTest {
    uint256 constant PROPOSER_AMOUNT = 1_500_000e18;

    function setUp() public override {
        super.setUp();

        vm.prank(admin);
        govToken.mint(alice, PROPOSER_AMOUNT);

        vm.prank(alice);
        govToken.delegate(alice);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 13);
    }

    function test_governor_cancel_pendingProposal() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(treasury);
        values[0] = 0;
        calldatas[0] = "";

        string memory description = "Cancel pending proposal";

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));

        vm.prank(alice);
        governor.cancel(targets, values, calldatas, keccak256(bytes(description)));

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Canceled));
    }
}

contract AMMAdditionalCoverageTest is BaseTest {
    function test_amm_initialize_success_directProxy() public {
        AMM impl = new AMM();

        bytes memory data = abi.encodeCall(AMM.initialize, (address(tokenA), address(tokenB), admin));

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        AMM initializedAmm = AMM(address(proxy));

        assertEq(address(initializedAmm.tokenA()), address(tokenA));
        assertEq(address(initializedAmm.tokenB()), address(tokenB));
        assertTrue(address(initializedAmm.lpToken()) != address(0));
        assertTrue(initializedAmm.hasRole(initializedAmm.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(initializedAmm.hasRole(initializedAmm.PAUSER_ROLE(), admin));
        assertTrue(initializedAmm.hasRole(initializedAmm.UPGRADER_ROLE(), admin));
    }

    function test_amm_initialize_reverts_zeroTokenA() public {
        AMM impl = new AMM();

        bytes memory data = abi.encodeCall(AMM.initialize, (address(0), address(tokenB), admin));

        vm.expectRevert(AMM.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function test_amm_initialize_reverts_zeroTokenB() public {
        AMM impl = new AMM();

        bytes memory data = abi.encodeCall(AMM.initialize, (address(tokenA), address(0), admin));

        vm.expectRevert(AMM.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function test_amm_initialize_reverts_zeroAdmin() public {
        AMM impl = new AMM();

        bytes memory data = abi.encodeCall(AMM.initialize, (address(tokenA), address(tokenB), address(0)));

        vm.expectRevert(AMM.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function test_amm_initialize_reverts_sameToken() public {
        AMM impl = new AMM();

        bytes memory data = abi.encodeCall(AMM.initialize, (address(tokenA), address(tokenA), admin));

        vm.expectRevert(AMM.InvalidToken.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function test_amm_upgrade_onlyUpgrader() public {
        AMM newImpl = new AMM();

        vm.prank(alice);
        vm.expectRevert();
        amm.upgradeToAndCall(address(newImpl), "");
    }

    function test_amm_upgrade_byAdmin() public {
        AMM newImpl = new AMM();

        vm.prank(admin);
        amm.upgradeToAndCall(address(newImpl), "");
    }

    function test_amm_pause_unpause_directCoverage() public {
        vm.prank(admin);
        amm.pause();

        vm.prank(admin);
        amm.unpause();
    }

    function test_amm_getAmountIn_reverts_onZeroReserve() public {
        vm.expectRevert(AMM.InsufficientLiquidity.selector);
        amm.getAmountIn(10e18, 0, 2000e18);
    }

    function test_amm_getAmountIn_reverts_whenOutputConsumesReserve() public {
        vm.expectRevert(AMM.InsufficientLiquidity.selector);
        amm.getAmountIn(2000e18, 1000e18, 2000e18);
    }

    function test_amm_addLiquidity_adjustsTokenAWhenTokenBIsLimiting() public {
        _addLiquidity(alice, 1000e18, 2000e18);

        vm.prank(bob);
        (uint256 aUsed, uint256 bUsed, uint256 lp) = amm.addLiquidity(9999e18, 500e18, 0, 0);

        assertEq(aUsed, 250e18);
        assertEq(bUsed, 500e18);
        assertGt(lp, 0);
    }

    function test_amm_addLiquidity_reverts_tokenAOptimalBelowMinimum() public {
        _addLiquidity(alice, 1000e18, 2000e18);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(AMM.SlippageExceeded.selector, 250e18, 300e18));
        amm.addLiquidity(9999e18, 500e18, 300e18, 0);
    }

    function test_amm_removeLiquidity_reverts_tokenBSlippage() public {
        uint256 lp = _addLiquidity(alice, 1000e18, 2000e18);

        vm.startPrank(alice);
        amm.lpToken().approve(address(amm), lp);
        vm.expectRevert();
        amm.removeLiquidity(lp, 0, 3000e18);
        vm.stopPrank();
    }
}

contract AMMFactoryAdditionalCoverageTest is BaseTest {
    function test_factory_constructor_reverts_zeroImplementation() public {
        vm.expectRevert(AMMFactory.ZeroAddress.selector);
        new AMMFactory(admin, address(0));
    }

    function test_factory_createPair_reverts_zeroToken() public {
        vm.prank(admin);
        vm.expectRevert(AMMFactory.ZeroAddress.selector);
        factory.createPair(address(0), address(tokenC));
    }

    function test_factory_predictPairAddress_sortsTokens() public view {
        address predictedForward = factory.predictPairAddress(address(tokenA), address(tokenC));
        address predictedReverse = factory.predictPairAddress(address(tokenC), address(tokenA));

        assertEq(predictedForward, predictedReverse);
    }

    function test_factory_pairLookupWorksBothDirections() public view {
        assertEq(factory.getPair(address(tokenA), address(tokenB)), address(amm));
        assertEq(factory.getPair(address(tokenB), address(tokenA)), address(amm));
    }
}

contract GovernanceTokenInitializationAdditionalTest is BaseTest {
    function test_governanceToken_initialize_success_directProxy() public {
        GovernanceToken impl = new GovernanceToken();

        bytes memory data = abi.encodeCall(GovernanceToken.initialize, (admin, admin, 100_000_000e18));

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        GovernanceToken token = GovernanceToken(address(proxy));

        assertEq(token.name(), "DeFiSuperApp Governance Token");
        assertEq(token.symbol(), "DSAT");
        assertEq(token.maxSupply(), 100_000_000e18);
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), admin));
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), admin));
    }

    function test_governanceToken_initialize_reverts_twice() public {
        GovernanceToken impl = new GovernanceToken();

        bytes memory data = abi.encodeCall(GovernanceToken.initialize, (admin, admin, 100_000_000e18));

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        GovernanceToken token = GovernanceToken(address(proxy));

        vm.expectRevert();
        token.initialize(admin, admin, 100_000_000e18);
    }
}
