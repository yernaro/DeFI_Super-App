// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../unit/BaseTest.t.sol";

contract FuzzTests is BaseTest {
    function setUp() public override {
        super.setUp();
        _addLiquidity(alice, 5000e18, 10_000e18);
        _supplyDebt(bob, 30_000e18);
    }


    function testFuzz_amm_kInvariant(uint256 amtIn, bool aToB) public {
        (uint112 rA, uint112 rB,) = amm.getReserves();
        uint256 k0 = uint256(rA) * uint256(rB);

        uint256 cap = aToB ? uint256(rA) / 100 : uint256(rB) / 100;
        amtIn = bound(amtIn, 1, cap == 0 ? 1 : cap);

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

    function testFuzz_amm_removeLiquidity_proportional(uint256 lpFraction) public {
        uint256 lp = _addLiquidity(carol, 2000e18, 4000e18);
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


    function testFuzz_vault_depositRedeem(uint256 assets) public {
        assets = bound(assets, 1e6, 10_000e18);
        tokenB.mint(alice, assets);
        vm.startPrank(alice);
        tokenB.approve(address(vault), assets);
        uint256 shares = vault.deposit(assets, alice);
        uint256 returned = vault.redeem(shares, alice, alice);
        vm.stopPrank();
        assertApproxEqAbs(returned, assets, 2);
    }

    function testFuzz_vault_mintWithdraw(uint256 shares) public {
        shares = bound(shares, 1e6, 1_000_000e18);

        uint256 assetsNeeded = vault.previewMint(shares);

        tokenB.mint(bob, assetsNeeded);

        vm.startPrank(bob);
        tokenB.approve(address(vault), assetsNeeded);

        uint256 assetsUsed = vault.mint(shares, bob);
        uint256 sharesBurned = vault.withdraw(assetsUsed, bob, bob);

        vm.stopPrank();

        assertApproxEqAbs(sharesBurned, shares, 2000);
}

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

    function testFuzz_govToken_votingPower(uint256 amount) public {
        uint256 cap = govToken.maxSupply() - govToken.totalSupply();
        amount = bound(amount, 1, cap);

        vm.prank(admin);
        govToken.mint(alice, amount);

        vm.prank(alice);
        govToken.delegate(alice);

        assertEq(govToken.getVotes(alice), amount);
    }

    function testFuzz_sqrt_correctness(uint256 x) public {
        x = bound(x, 0, type(uint128).max);

        uint256 yulResult = MathUtils.sqrt(x);
        uint256 solidityResult = MathUtils.sqrtSolidity(x);

        assertEq(yulResult, solidityResult);
    }

    function testFuzz_mulDiv_matchesSolidity(uint128 a, uint128 b, uint128 denom) public {
        denom = uint128(bound(uint256(denom), 1, type(uint128).max));

        uint256 yul = MathUtils.mulDiv(a, b, denom);
        uint256 solRef = MathUtils.mulDivSolidity(a, b, denom);

        assertEq(yul, solRef);
    }

    function testFuzz_oracle_validAnswerReturnsPositivePrice(uint80 answer18Dec) public {
        uint256 answerBounded = bound(uint256(answer18Dec), 1e8, 100_000e8);

        vm.prank(admin);
        feedA.setAnswer(int256(answerBounded));

        uint256 price = oracle.getPrice(address(tokenA));

        assertGt(price, 0);
        assertEq(price, answerBounded * 10 ** (18 - 8));
    }
}