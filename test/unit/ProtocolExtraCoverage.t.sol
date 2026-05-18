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
}

contract LendingPoolAdditionalCoverageTest is BaseTest {
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
