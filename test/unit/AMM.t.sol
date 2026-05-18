// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./BaseTest.t.sol";

contract AMMTest is BaseTest {
    function test_ammInitialization() public view {
        assertEq(address(amm.tokenA()), address(tokenA));
        assertEq(address(amm.tokenB()), address(tokenB));
        assertTrue(address(amm.lpToken()) != address(0));
    }

    function test_ammHasCorrectFeeConstants() public view {
        assertEq(amm.FEE_NUMERATOR(), 3);
        assertEq(amm.FEE_DENOMINATOR(), 1000);
    }

    function test_addLiquidity_firstDeposit() public {
        uint256 amtA = 1000e18;
        uint256 amtB = 2000e18;
        vm.prank(alice);
        (uint256 a, uint256 b, uint256 lp) = amm.addLiquidity(amtA, amtB, 0, 0);

        assertEq(a, amtA);
        assertEq(b, amtB);
        uint256 expectedLP = MathUtils.sqrt(amtA * amtB) - amm.MINIMUM_LIQUIDITY();
        assertEq(lp, expectedLP);
        assertEq(amm.lpToken().balanceOf(alice), expectedLP);
    }

    function test_addLiquidity_secondDeposit_proportional() public {
        _addLiquidity(alice, 1000e18, 2000e18);

        vm.prank(bob);
        (uint256 a, uint256 b, uint256 lp) = amm.addLiquidity(500e18, 1000e18, 0, 0);
        assertEq(a, 500e18);
        assertEq(b, 1000e18);
        assertTrue(lp > 0);
    }

    function test_addLiquidity_adjustsToReserveRatio() public {
        _addLiquidity(alice, 1000e18, 2000e18);

        vm.prank(bob);
        (, uint256 bUsed,) = amm.addLiquidity(500e18, 9999e18, 0, 0);
        assertEq(bUsed, 1000e18);
    }

    function test_addLiquidity_reverts_onZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(AMM.ZeroAmount.selector);
        amm.addLiquidity(0, 1000e18, 0, 0);
    }

    function test_addLiquidity_reverts_onSlippage() public {
        _addLiquidity(alice, 1000e18, 2000e18);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(AMM.SlippageExceeded.selector, 1000e18, 9000e18));
        amm.addLiquidity(500e18, 9000e18, 0, 9000e18);
    }

    function test_addLiquidity_reverts_whenPaused() public {
        vm.prank(admin);
        amm.pause();

        vm.prank(alice);
        vm.expectRevert();
        amm.addLiquidity(1000e18, 2000e18, 0, 0);
    }

    function test_removeLiquidity_receivesProportional() public {
        uint256 lp = _addLiquidity(alice, 1000e18, 2000e18);
        uint256 balABefore = tokenA.balanceOf(alice);
        uint256 balBBefore = tokenB.balanceOf(alice);

        vm.startPrank(alice);
        amm.lpToken().approve(address(amm), lp);
        (uint256 outA, uint256 outB) = amm.removeLiquidity(lp, 0, 0);
        vm.stopPrank();

        assertApproxEqAbs(outA, 1000e18, 1e15);
        assertApproxEqAbs(outB, 2000e18, 1e15);
        assertEq(tokenA.balanceOf(alice), balABefore + outA);
        assertEq(tokenB.balanceOf(alice), balBBefore + outB);
    }

    function test_removeLiquidity_reverts_onZeroLP() public {
        _addLiquidity(alice, 1000e18, 2000e18);
        vm.prank(alice);
        vm.expectRevert(AMM.ZeroAmount.selector);
        amm.removeLiquidity(0, 0, 0);
    }

    function test_removeLiquidity_reverts_onSlippage() public {
        uint256 lp = _addLiquidity(alice, 1000e18, 2000e18);
        vm.startPrank(alice);
        amm.lpToken().approve(address(amm), lp);
        vm.expectRevert();
        amm.removeLiquidity(lp, 9999e18, 0);
        vm.stopPrank();
    }

    function test_swap_aToBCorrectOutput() public {
        _addLiquidity(alice, 1000e18, 2000e18);

        uint256 amtIn = 10e18;
        (uint112 rA, uint112 rB,) = amm.getReserves();
        uint256 expected = amm.getAmountOut(amtIn, rA, rB);

        uint256 balBefore = tokenB.balanceOf(bob);
        vm.prank(bob);
        uint256 amtOut = amm.swap(amtIn, 0, true, bob);

        assertEq(amtOut, expected);
        assertEq(tokenB.balanceOf(bob), balBefore + amtOut);
    }

    function test_swap_bToACorrectOutput() public {
        _addLiquidity(alice, 1000e18, 2000e18);
        uint256 amtIn = 100e18;
        (uint112 rA, uint112 rB,) = amm.getReserves();
        uint256 expected = amm.getAmountOut(amtIn, rB, rA);

        uint256 balBefore = tokenA.balanceOf(bob);
        vm.prank(bob);
        uint256 amtOut = amm.swap(amtIn, 0, false, bob);

        assertEq(amtOut, expected);
        assertEq(tokenA.balanceOf(bob), balBefore + amtOut);
    }

    function test_swap_reverts_onZeroInput() public {
        _addLiquidity(alice, 1000e18, 2000e18);
        vm.prank(bob);
        vm.expectRevert(AMM.InsufficientInputAmount.selector);
        amm.swap(0, 0, true, bob);
    }

    function test_swap_reverts_onSlippage() public {
        _addLiquidity(alice, 1000e18, 2000e18);
        vm.prank(bob);
        vm.expectRevert();
        amm.swap(10e18, 999e18, true, bob);
    }

    function test_swap_reverts_onZeroRecipient() public {
        _addLiquidity(alice, 1000e18, 2000e18);
        vm.prank(bob);
        vm.expectRevert(AMM.ZeroAddress.selector);
        amm.swap(10e18, 0, true, address(0));
    }

    function test_swap_reverts_whenPaused() public {
        _addLiquidity(alice, 1000e18, 2000e18);
        vm.prank(admin);
        amm.pause();
        vm.prank(bob);
        vm.expectRevert();
        amm.swap(10e18, 0, true, bob);
    }

    function test_swap_updatesReserves() public {
        _addLiquidity(alice, 1000e18, 2000e18);
        (uint112 rA0, uint112 rB0,) = amm.getReserves();
        uint256 amtIn = 10e18;
        vm.prank(bob);
        uint256 amtOut = amm.swap(amtIn, 0, true, bob);

        (uint112 rA1, uint112 rB1,) = amm.getReserves();
        assertEq(rA1, rA0 + amtIn);
        assertEq(rB1, rB0 - amtOut);
    }

    function test_swap_kIncreasesOrStaysFlat() public {
        _addLiquidity(alice, 1000e18, 2000e18);
        (uint112 rA0, uint112 rB0,) = amm.getReserves();
        uint256 k0 = uint256(rA0) * uint256(rB0);

        vm.prank(bob);
        amm.swap(10e18, 0, true, bob);

        (uint112 rA1, uint112 rB1,) = amm.getReserves();
        uint256 k1 = uint256(rA1) * uint256(rB1);
        assertGe(k1, k0);
    }

    function test_getAmountOut_reverts_onZeroInput() public {
        vm.expectRevert(AMM.InsufficientInputAmount.selector);
        amm.getAmountOut(0, 1000e18, 2000e18);
    }

    function test_getAmountOut_reverts_onZeroReserve() public {
        vm.expectRevert(AMM.InsufficientLiquidity.selector);
        amm.getAmountOut(10e18, 0, 2000e18);
    }

    function test_getAmountIn_reverts_onZeroOutput() public {
        vm.expectRevert(AMM.InsufficientOutputAmount.selector);
        amm.getAmountIn(0, 1000e18, 2000e18);
    }

    function test_getAmountIn_roundtrip() public view {
        uint256 reserveIn = 1000e18;
        uint256 reserveOut = 2000e18;
        uint256 desiredOut = 50e18;
        uint256 requiredIn = amm.getAmountIn(desiredOut, reserveIn, reserveOut);
        uint256 actualOut = amm.getAmountOut(requiredIn, reserveIn, reserveOut);
        assertGe(actualOut, desiredOut);
    }

    function test_pause_onlyPauserRole() public {
        vm.prank(alice);
        vm.expectRevert();
        amm.pause();
    }

    function test_pauseAndUnpause() public {
        vm.prank(admin);
        amm.pause();
        assertTrue(amm.paused());

        vm.prank(admin);
        amm.unpause();
        assertFalse(amm.paused());
    }

    function test_factory_createPair_registers() public view {
        address pair = factory.getPair(address(tokenA), address(tokenB));
        assertEq(pair, address(amm));
        assertEq(factory.allPairsLength(), 1);
    }

    function test_factory_createPair_create2_deterministic() public {
        vm.startPrank(admin);
        address predicted = factory.predictPairAddress(address(tokenA), address(tokenC));
        address created = factory.createPairDeterministic(address(tokenA), address(tokenC));
        vm.stopPrank();
        assertEq(created, predicted);
    }

    function test_factory_reverts_onDuplicatePair() public {
        vm.prank(admin);
        vm.expectRevert();
        factory.createPair(address(tokenA), address(tokenB));
    }

    function test_factory_reverts_onIdenticalTokens() public {
        vm.prank(admin);
        vm.expectRevert(AMMFactory.IdenticalTokens.selector);
        factory.createPair(address(tokenA), address(tokenA));
    }

    function test_sqrt_matchesReference() public pure {
        uint256[] memory inputs = new uint256[](5);
        inputs[0] = 0;
        inputs[1] = 1;
        inputs[2] = 4;
        inputs[3] = 1e36;
        inputs[4] = type(uint128).max;
        for (uint256 i = 0; i < inputs.length; i++) {
            assertEq(MathUtils.sqrt(inputs[i]), MathUtils.sqrtSolidity(inputs[i]));
        }
    }

    function test_mulDiv_basicCase() public pure {
        assertEq(MathUtils.mulDiv(10, 20, 5), 40);
    }

    function test_mulDiv_matchesReference() public pure {
        assertEq(MathUtils.mulDiv(1e18, 1e18, 1e9), MathUtils.mulDivSolidity(1e18, 1e18, 1e9));
    }

    function test_mathUtils_minMax() public pure {
        assertEq(MathUtils.min(3, 5), 3);
        assertEq(MathUtils.max(3, 5), 5);
        assertEq(MathUtils.min(0, 0), 0);
    }
}
