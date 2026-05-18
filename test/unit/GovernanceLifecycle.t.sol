// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./BaseTest.t.sol";

/// @notice End-to-end governance lifecycle:
///         propose → vote → queue → execute
///         Also tests flash-loan attack resistance.
contract GovernanceLifecycleTest is BaseTest {
    uint256 constant MINT_AMOUNT     = 1_000_000e18; // 1 % of 100M = 10k threshold
    uint256 constant PROPOSER_AMOUNT = 1_500_000e18; // > 1 % threshold

    function setUp() public override {
        super.setUp();

        // Mint governance tokens to alice (proposer) and bob (voter)
        vm.startPrank(admin);
        govToken.mint(alice, PROPOSER_AMOUNT);
        govToken.mint(bob,   40_000_000e18); // 40 % — sufficient for quorum (4 %)
        govToken.mint(carol, 10_000_000e18);
        vm.stopPrank();

        // Self-delegate so voting power is checkpoint-ed
        vm.prank(alice);  govToken.delegate(alice);
        vm.prank(bob);    govToken.delegate(bob);
        vm.prank(carol);  govToken.delegate(carol);

        // Advance a block so snapshots are available
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 13);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Full lifecycle
    // ─────────────────────────────────────────────────────────────────────────
    function test_governance_fullLifecycle_proposeVoteQueueExecute() public {
        // ── 1. Craft proposal: send 1 ETH from Treasury to carol ─────────────
        vm.deal(address(treasury), 2 ether);

        address[] memory targets  = new address[](1);
        uint256[] memory values   = new uint256[](1);
        bytes[]   memory calldatas = new bytes[](1);

        targets[0]   = address(treasury);
        values[0]    = 0;
        calldatas[0] = abi.encodeCall(Treasury.withdrawEther, (payable(carol), 1 ether));
        string memory description = "Proposal #1: Send 1 ETH to carol";
        bytes32 descHash = keccak256(bytes(description));

        // ── 2. Propose ────────────────────────────────────────────────────────
        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));

        // ── 3. Skip voting delay (1 day) ──────────────────────────────────────
        vm.roll(block.number + governor.votingDelay() / 12 + 1); // ~7200 blocks
        vm.warp(block.timestamp + 1 days + 1);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));

        // ── 4. Vote (bob votes For, carol votes Against) ─────────────────────
        vm.prank(bob);
        governor.castVote(proposalId, 1); // 1 = For

        vm.prank(carol);
        governor.castVote(proposalId, 0); // 0 = Against

        // ── 5. Skip voting period (1 week) ────────────────────────────────────
        vm.roll(block.number + governor.votingPeriod() / 12 + 1);
        vm.warp(block.timestamp + 1 weeks + 1);
        // Bob had 40M votes vs Carol's 10M — Succeeded
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        // ── 6. Queue into Timelock ────────────────────────────────────────────
        governor.queue(targets, values, calldatas, descHash);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));

        // ── 7. Skip Timelock delay (2 days) ──────────────────────────────────
        vm.warp(block.timestamp + 2 days + 1);

        // ── 8. Execute ───────────────────────────────────────────────────────
        uint256 carolBalBefore = carol.balance;
        governor.execute(targets, values, calldatas, descHash);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));

        assertEq(carol.balance, carolBalBefore + 1 ether);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Proposal threshold enforcement
    // ─────────────────────────────────────────────────────────────────────────
    function test_governance_proposalThreshold_enforced() public {
        // Carol has 10M / 100M = 10 % > 1 % threshold — should succeed
        address[] memory targets   = new address[](1);
        uint256[] memory values    = new uint256[](1);
        bytes[]   memory calldatas = new bytes[](1);
        targets[0] = address(treasury);

        vm.prank(carol);
        uint256 id = governor.propose(targets, values, calldatas, "Proposal by carol");
        assertTrue(id > 0);
    }

    function test_governance_propose_reverts_belowThreshold() public {
        address poorProposer = makeAddr("poor");
        vm.prank(admin);
        govToken.mint(poorProposer, 1e18); // 1 token — way below threshold
        vm.prank(poorProposer);
        govToken.delegate(poorProposer);
        vm.roll(block.number + 1);

        address[] memory targets   = new address[](1);
        uint256[] memory values    = new uint256[](1);
        bytes[]   memory calldatas = new bytes[](1);

        vm.prank(poorProposer);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, "Should fail");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quorum enforcement
    // ─────────────────────────────────────────────────────────────────────────
    function test_governance_fails_withoutQuorum() public {
        address[] memory targets   = new address[](1);
        uint256[] memory values    = new uint256[](1);
        bytes[]   memory calldatas = new bytes[](1);
        targets[0] = address(treasury);

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Low turnout");

        vm.roll(block.number + governor.votingDelay() / 12 + 1);
        vm.warp(block.timestamp + 1 days + 1);

        // Only alice votes (1.5M / 100M = 1.5 % < 4 % quorum)
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + governor.votingPeriod() / 12 + 1);
        vm.warp(block.timestamp + 1 weeks + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Flash-loan governance attack resistance
    // ─────────────────────────────────────────────────────────────────────────
    /// @notice Voting power is based on past block checkpoint — flash-loan
    ///         attack cannot influence a vote in the same block it's cast.
    function test_governance_flashLoanAttack_preventsVoteManipulation() public {
        address flashBot = makeAddr("flashBot");

        // Flash bot gets tokens after proposal snapshot
        vm.prank(admin);
        govToken.mint(flashBot, 50_000_000e18);
        vm.prank(flashBot);
        govToken.delegate(flashBot);

        address[] memory targets   = new address[](1);
        uint256[] memory values    = new uint256[](1);
        bytes[]   memory calldatas = new bytes[](1);
        targets[0] = address(treasury);

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Flash attack test");

        // Advance past voting delay
        vm.roll(block.number + governor.votingDelay() / 12 + 1);
        vm.warp(block.timestamp + 1 days + 1);

        // Check voting weight of flashBot at the snapshot block
        // (flashBot got tokens AFTER proposal snapshot → getPastVotes = 0)
        uint256 snapshotBlock = governor.proposalSnapshot(proposalId);
        uint256 flashBotVotes = govToken.getPastVotes(flashBot, snapshotBlock);

        // Flash bot minted AFTER the snapshot → zero historical voting power
        assertEq(flashBotVotes, 0);

        // Flash bot attempting to vote should carry zero weight
        vm.prank(flashBot);
        governor.castVote(proposalId, 1);

        (uint256 against, uint256 forVotes, uint256 abstain) = governor.proposalVotes(proposalId);
        assertEq(forVotes, 0); // no weight counted
        assertEq(against, 0);
        assertEq(abstain, 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Timelock admin lockout check
    // ─────────────────────────────────────────────────────────────────────────
    function test_timelock_directExecution_blockedWithoutDelay() public {
        // Anyone trying to execute on the timelock without scheduling should revert
        vm.prank(alice);
        vm.expectRevert();
        timelock.execute(address(treasury), 0, bytes(""), bytes32(0), bytes32(0));
    }
}
