// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../../src/assembly/MathUtils.sol";

contract MathUtilsWrapper {
    function mulDivExternal(uint256 a, uint256 b, uint256 denominator) external pure returns (uint256) {
        return MathUtils.mulDiv(a, b, denominator);
    }

    function mulDivSolidityExternal(uint256 a, uint256 b, uint256 denominator) external pure returns (uint256) {
        return MathUtils.mulDivSolidity(a, b, denominator);
    }
}

contract MathUtilsExtraCoverageTest is Test {
    MathUtilsWrapper wrapper;

    function setUp() public {
        wrapper = new MathUtilsWrapper();
    }

    function test_sqrt_edgeCases() public pure {
        assertEq(MathUtils.sqrt(0), 0);
        assertEq(MathUtils.sqrt(1), 1);
        assertEq(MathUtils.sqrt(2), 1);
        assertEq(MathUtils.sqrt(3), 1);
        assertEq(MathUtils.sqrt(4), 2);
        assertEq(MathUtils.sqrt(9), 3);
        assertEq(MathUtils.sqrt(15), 3);
        assertEq(MathUtils.sqrt(16), 4);
        assertEq(MathUtils.sqrt(17), 4);
    }

    function test_sqrt_thresholdBranches() public pure {
        assertEq(MathUtils.sqrt(2 ** 2), 2);
        assertEq(MathUtils.sqrt(2 ** 4), 4);
        assertEq(MathUtils.sqrt(2 ** 8), 16);
        assertEq(MathUtils.sqrt(2 ** 16), 256);
        assertEq(MathUtils.sqrt(2 ** 32), 65536);
        assertEq(MathUtils.sqrt(2 ** 64), 4294967296);
        assertEq(MathUtils.sqrt(2 ** 128), 18446744073709551616);
    }

    function test_sqrt_matchesSolidityReference() public pure {
        assertEq(MathUtils.sqrt(2), MathUtils.sqrtSolidity(2));
        assertEq(MathUtils.sqrt(3), MathUtils.sqrtSolidity(3));
        assertEq(MathUtils.sqrt(10), MathUtils.sqrtSolidity(10));
        assertEq(MathUtils.sqrt(10_000), MathUtils.sqrtSolidity(10_000));
    }

    function test_sqrtSolidity_edgeCases() public pure {
        assertEq(MathUtils.sqrtSolidity(0), 0);
        assertEq(MathUtils.sqrtSolidity(1), 1);
        assertEq(MathUtils.sqrtSolidity(2), 1);
        assertEq(MathUtils.sqrtSolidity(3), 1);
        assertEq(MathUtils.sqrtSolidity(4), 2);
        assertEq(MathUtils.sqrtSolidity(15), 3);
        assertEq(MathUtils.sqrtSolidity(16), 4);
        assertEq(MathUtils.sqrtSolidity(17), 4);
    }

    function test_sqrtSolidity_thresholdBranches() public pure {
        assertEq(MathUtils.sqrtSolidity(2 ** 2), 2);
        assertEq(MathUtils.sqrtSolidity(2 ** 4), 4);
        assertEq(MathUtils.sqrtSolidity(2 ** 8), 16);
        assertEq(MathUtils.sqrtSolidity(2 ** 16), 256);
        assertEq(MathUtils.sqrtSolidity(2 ** 32), 65536);
        assertEq(MathUtils.sqrtSolidity(2 ** 64), 4294967296);
        assertEq(MathUtils.sqrtSolidity(2 ** 128), 18446744073709551616);
    }

    function test_sqrt_largePerfectSquare() public pure {
        uint256 n = type(uint128).max;
        uint256 x = n * n;

        assertEq(MathUtils.sqrt(x), n);
    }

    function test_sqrt_largeNonPerfectSquare() public pure {
        uint256 n = type(uint128).max;
        uint256 x = n * n - 1;

        assertEq(MathUtils.sqrt(x), n - 1);
    }

    function test_sqrtSolidity_largePerfectSquare() public pure {
        uint256 n = type(uint128).max;
        uint256 x = n * n;

        assertEq(MathUtils.sqrtSolidity(x), n);
    }

    function test_sqrtSolidity_largeNonPerfectSquare() public pure {
        uint256 n = type(uint128).max;
        uint256 x = n * n - 1;

        assertEq(MathUtils.sqrtSolidity(x), n - 1);
    }

    function test_mulDiv_zeroValues() public pure {
        assertEq(MathUtils.mulDiv(0, 100, 5), 0);
        assertEq(MathUtils.mulDiv(100, 0, 5), 0);
    }

    function test_mulDiv_roundsDown() public pure {
        assertEq(MathUtils.mulDiv(10, 10, 6), 16);
        assertEq(MathUtils.mulDiv(7, 5, 2), 17);
    }

    function test_mulDiv_fullPrecisionPath() public pure {
        uint256 result = MathUtils.mulDiv(
            type(uint256).max,
            type(uint256).max,
            type(uint256).max
        );

        assertEq(result, type(uint256).max);
    }

    function test_mulDiv_reverts_zeroDenominator() public {
        vm.expectRevert();
        wrapper.mulDivExternal(1, 1, 0);
    }

    function test_mulDiv_reverts_overflow() public {
        vm.expectRevert();
        wrapper.mulDivExternal(
            type(uint256).max,
            type(uint256).max,
            type(uint256).max - 1
        );
    }

    function test_mulDivSolidity_basicCases() public pure {
        assertEq(MathUtils.mulDivSolidity(10, 10, 6), 16);
        assertEq(MathUtils.mulDivSolidity(7, 5, 2), 17);
        assertEq(MathUtils.mulDivSolidity(0, 100, 5), 0);
        assertEq(MathUtils.mulDivSolidity(100, 0, 5), 0);
    }

    function test_mulDivSolidity_reverts_zeroDenominator() public {
        vm.expectRevert(bytes("MathUtils: zero denom"));
        wrapper.mulDivSolidityExternal(1, 1, 0);
    }

    function test_mulDivSolidity_reverts_overflow() public {
        vm.expectRevert();
        wrapper.mulDivSolidityExternal(type(uint256).max, 2, 1);
    }

    function test_min_edgeCases() public pure {
        assertEq(MathUtils.min(1, 2), 1);
        assertEq(MathUtils.min(2, 1), 1);
        assertEq(MathUtils.min(5, 5), 5);
        assertEq(MathUtils.min(0, type(uint256).max), 0);
    }

    function test_max_edgeCases() public pure {
        assertEq(MathUtils.max(1, 2), 2);
        assertEq(MathUtils.max(2, 1), 2);
        assertEq(MathUtils.max(5, 5), 5);
        assertEq(MathUtils.max(0, type(uint256).max), type(uint256).max);
    }
}
