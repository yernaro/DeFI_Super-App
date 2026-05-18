// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./BaseTest.t.sol";

contract GovernanceLifecycleTest is BaseTest {
    uint256 constant PROPOSER_AMOUNT = 1_500_000e18;

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        govToken.mint(alice, PROPOSER_AMOUNT);
        govToken.mint(bob, 40_000_000e18);
        govToken.mint(carol, 10_000_000e18);
        vm.stopPrank();

        vm.prank(alice);
        govToken.delegate(alice);

        vm.prank(bob);
        govToken.delegate(bob);

        vm.prank(carol);
        govToken.delegate(carol);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 13);
    }

    function test_governance_fullLifecycle_proposeVoteQueueExecute() public {
        vm.deal(address(treasury), 2 ether);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(treasury);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(Treasury.withdrawEther, (payable(carol), 1 ether));

        string memory description = "Proposal #1: Send 1 ETH to carol";
        bytes32 descHash = keccak256(bytes(description));

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));

        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        vm.warp(block.timestamp + 1 days + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));

        vm.prank(bob);
        governor.castVote(proposalId, 1);

        vm.prank(carol);
        governor.castVote(proposalId, 0);

        vm.roll(governor.proposalDeadline(proposalId) + 1);
        vm.warp(block.timestamp + 1 weeks + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        governor.queue(targets, values, calldatas, descHash);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));

        vm.warp(block.timestamp + 2 days + 1);

        uint256 carolBalBefore = carol.balance;

        governor.execute(targets, values, calldatas, descHash);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
        assertEq(carol.balance, carolBalBefore + 1 ether);
    }

    function test_governance_proposalThreshold_enforced() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(treasury);
        values[0] = 0;
        calldatas[0] = "";

        vm.prank(carol);
        uint256 id = governor.propose(targets, values, calldatas, "Proposal by carol");

        assertTrue(id > 0);
    }

    function test_governance_propose_reverts_belowThreshold() public {
        address poorProposer = makeAddr("poor");

        vm.prank(admin);
        govToken.mint(poorProposer, 1e18);

        vm.prank(poorProposer);
        govToken.delegate(poorProposer);

        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(treasury);
        values[0] = 0;
        calldatas[0] = "";

        vm.prank(poorProposer);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, "Should fail");
    }

    function test_governance_fails_withoutQuorum() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(treasury);
        values[0] = 0;
        calldatas[0] = "";

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Low turnout");

        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        vm.warp(block.timestamp + 1 days + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));

        vm.prank(alice);
        governor.castVote(proposalId, 1);

        vm.roll(governor.proposalDeadline(proposalId) + 1);
        vm.warp(block.timestamp + 1 weeks + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    function test_governance_flashLoanAttack_preventsVoteManipulation() public {
        address flashBot = makeAddr("flashBot");

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(treasury);
        values[0] = 0;
        calldatas[0] = "";

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Flash attack test");

        uint256 snapshotBlock = governor.proposalSnapshot(proposalId);

        vm.roll(snapshotBlock + 1);
        vm.warp(block.timestamp + 1 days + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));

        uint256 remainingSupply = govToken.maxSupply() - govToken.totalSupply();

        vm.prank(admin);
        govToken.mint(flashBot, remainingSupply);

        vm.prank(flashBot);
        govToken.delegate(flashBot);

        uint256 flashBotVotes = govToken.getPastVotes(flashBot, snapshotBlock);

        assertEq(flashBotVotes, 0);

        vm.prank(flashBot);
        governor.castVote(proposalId, 1);

        (uint256 against, uint256 forVotes, uint256 abstain) = governor.proposalVotes(proposalId);

        assertEq(forVotes, 0);
        assertEq(against, 0);
        assertEq(abstain, 0);
    }

    function test_timelock_directExecution_blockedWithoutDelay() public {
        vm.prank(alice);
        vm.expectRevert();
        timelock.execute(address(treasury), 0, bytes(""), bytes32(0), bytes32(0));
    }
}
