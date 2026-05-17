// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../unit/BaseTest.t.sol";

/// @notice Fuzz tests — minimum 10 as required by the spec.
contract FuzzTests is BaseTest {
    function setUp() public override {
        super.setUp();
        // Seed the AMM with initial liquidity so fuzzing can swap
        _addLiquidity(alice, 5000e18, 10_000e18);
        // Seed lending pool
        _supplyDebt(bob, 30_000e18);
    }

    // ── AMM Fuzz (3) ─────────────────────────────────────────────────────────

    /// @notice k never decreases after any swap (constant-product invariant).
    function testFuzz_amm_kInvariant(uint256 amtIn, bool aToB) public {
        (uint112 rA, uint112 rB,) = amm.getReserves();
        uint256 k0 = uint256(rA) * uint256(rB);

        // Bound amtIn to [1 wei, 1 % of reserve] to keep swap feasible
        uint256 cap = aToB ? uint256(rA) / 100 : uint256(rB) / 100;
        amtIn = bound(amtIn, 1, cap == 0 ? 1 : cap);

        // Give bob enough tokens
        if (aToB) {
            tokenA.mint(bob, amtIn);
            vm.prank(bob);
            tokenA.approve(address(amm), amtIn);
        } else {
            tokenB.mint(bob, amtIn);
            vm.prank(bob);
            tokenB.approve(address(amm), amtIn);
        }

        vm.prank(bob);
        amm.swap(amtIn, 0, aToB, bob);

        (uint112 rA1, uint112 rB1,) = amm.getReserves();
        uint256 k1 = uint256(rA1) * uint256(rB1);
        assertGe(k1, k0);
    }

    /// @notice amountOut from getAmountOut is consistent with actual swap output.
    function testFuzz_amm_quotedOutputMatchesActual(uint256 amtIn) public {
        (uint112 rA, uint112 rB,) = amm.getReserves();
        amtIn = bound(amtIn, 1, uint256(rA) / 50);

        uint256 quoted = amm.getAmountOut(amtIn, rA, rB);

        tokenA.mint(carol, amtIn);
        vm.startPrank(carol);
        tokenA.approve(address(amm), amtIn);
        uint256 actual = amm.swap(amtIn, 0, true, carol);
        vm.stopPrank();

        assertEq(actual, quoted);
    }

    /// @notice Removing liquidity proportionally returns correct reserves.
    function testFuzz_amm_removeLiquidity_proportional(uint256 lpFraction) public {
        uint256 lp = _addLiquidity(carol, 2000e18, 4000e18);
        // Remove between 1 % and 100 % of LP
        lpFraction = bound(lpFraction, 1, 100);
        uint256 toRemove = lp * lpFraction / 100;

        (uint112 rA, uint112 rB,) = amm.getReserves();
        uint256 totalLP = amm.lpToken().totalSupply();

        uint256 expectedA = toRemove * rA / totalLP;
        uint256 expectedB = toRemove * rB / totalLP;

        vm.startPrank(carol);
        amm.lpToken().approve(address(amm), toRemove);
        (uint256 outA, uint256 outB) = amm.removeLiquidity(toRemove, 0, 0);
        vm.stopPrank();

        assertApproxEqAbs(outA, expectedA, 1);
        assertApproxEqAbs(outB, expectedB, 1);
    }

    // ── Vault Fuzz (3) ────────────────────────────────────────────────────────

    /// @notice Deposit → redeem roundtrip: assets out ≥ assets in (no-harvest scenario).
    function testFuzz_vault_depositRedeem(uint256 assets) public {
        assets = bound(assets, 1e6, 10_000e18);
        tokenB.mint(alice, assets);
        vm.startPrank(alice);
        tokenB.approve(address(vault), assets);
        uint256 shares = vault.deposit(assets, alice);
        uint256 returned = vault.redeem(shares, alice, alice);
        vm.stopPrank();
        // Due to virtual offset, returned may be slightly less (< 2 wei)
        assertApproxEqAbs(returned, assets, 2);
    }

    /// @notice mint → withdraw: shares burned matches preview.
    function testFuzz_vault_mintWithdraw(uint256 shares) public {
        shares = bound(shares, 1e6, 1_000_000e18);
        // Ensure enough assets
        uint256 assetsNeeded = vault.previewMint(shares);
        tokenB.mint(bob, assetsNeeded);
        vm.startPrank(bob);
        tokenB.approve(address(vault), assetsNeeded);
        uint256 assetsUsed = vault.mint(shares, bob);
        uint256 sharesBurned = vault.withdraw(assetsUsed, bob, bob);
        vm.stopPrank();
        assertApproxEqAbs(sharesBurned, shares, 1);
    }

    /// @notice totalAssets never decreases after a deposit.
    function testFuzz_vault_totalAssetsMonotonicallyIncreasing(uint256 a1, uint256 a2) public {
        a1 = bound(a1, 1e6, 5000e18);
        a2 = bound(a2, 1e6, 5000e18);
        tokenB.mint(alice, a1 + a2);
        vm.startPrank(alice);
        tokenB.approve(address(vault), a1 + a2);
        uint256 ta0 = vault.totalAssets();
        vault.deposit(a1, alice);
        uint256 ta1 = vault.totalAssets();
        vault.deposit(a2, alice);
        uint256 ta2 = vault.totalAssets();
        vm.stopPrank();
        assertGe(ta1, ta0);
        assertGe(ta2, ta1);
    }

    // ── Governance Fuzz (2) ──────────────────────────────────────────────────

    /// @notice Voting power matches minted tokens (after self-delegation).
    function testFuzz_govToken_votingPower(uint256 amount) public {
        uint256 cap = govToken.maxSupply() - govToken.totalSupply();
        amount = bound(amount, 1, cap);

        vm.prank(admin);
        govToken.mint(alice, amount);

        vm.prank(alice);
        govToken.delegate(alice);

        assertEq(govToken.getVotes(alice), amount);
    }

    /// @notice MathUtils.sqrt(x) == floor(√x) for all inputs.
    function testFuzz_sqrt_correctness(uint256 x) public pure {
        uint256 s = MathUtils.sqrt(x);
        // floor condition: s² ≤ x < (s+1)²
        assertLe(s * s, x);
        if (s < type(uint128).max) {
            assertGt((s + 1) * (s + 1), x);
        }
    }

    /// @notice mulDiv(a, b, denom) == a*b/denom for safe inputs.
    function testFuzz_mulDiv_matchesSolidity(uint128 a, uint128 b, uint128 denom) public pure {
        vm.assume(denom > 0);
        uint256 yul     = MathUtils.mulDiv(a, b, denom);
        uint256 solRef  = MathUtils.mulDivSolidity(a, b, denom);
        assertEq(yul, solRef);
    }
}

    // ── Oracle Fuzz (1) ───────────────────────────────────────────────────────

    /// @notice Oracle always returns price > 0 for valid (non-stale, non-negative) answers.
    function testFuzz_oracle_validAnswerReturnsPositivePrice(uint80 answer18Dec) public {
        // Bound to a realistic ETH price range: $1 to $100,000
        uint256 answerBounded = bound(uint256(answer18Dec), 1e8, 100_000e8); // 8-decimal Chainlink answer
        vm.prank(admin);
        feedA.setAnswer(int256(answerBounded));

        uint256 price = oracle.getPrice(address(tokenA));
        assertGt(price, 0);
        // Price should normalise correctly to 18 decimals
        assertEq(price, answerBounded * 10 ** (18 - 8));
    }
