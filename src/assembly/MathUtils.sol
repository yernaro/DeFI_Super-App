// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

library MathUtils {
    function sqrt(uint256 x) internal pure returns (uint256 z) {
        if (x == 0) return 0;

        z = 1;
        uint256 y = x;

        if (y >= 2 ** 128) {
            y >>= 128;
            z <<= 64;
        }
        if (y >= 2 ** 64) {
            y >>= 64;
            z <<= 32;
        }
        if (y >= 2 ** 32) {
            y >>= 32;
            z <<= 16;
        }
        if (y >= 2 ** 16) {
            y >>= 16;
            z <<= 8;
        }
        if (y >= 2 ** 8) {
            y >>= 8;
            z <<= 4;
        }
        if (y >= 2 ** 4) {
            y >>= 4;
            z <<= 2;
        }
        if (y >= 2 ** 2) {
            z <<= 1;
        }

        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;

        uint256 zRoundedDown = x / z;
        if (zRoundedDown < z) {
            z = zRoundedDown;
        }
    }

    function sqrtSolidity(uint256 x) internal pure returns (uint256 z) {
        if (x == 0) return 0;

        z = 1;
        uint256 y = x;

        if (y >= 2 ** 128) {
            y >>= 128;
            z <<= 64;
        }
        if (y >= 2 ** 64) {
            y >>= 64;
            z <<= 32;
        }
        if (y >= 2 ** 32) {
            y >>= 32;
            z <<= 16;
        }
        if (y >= 2 ** 16) {
            y >>= 16;
            z <<= 8;
        }
        if (y >= 2 ** 8) {
            y >>= 8;
            z <<= 4;
        }
        if (y >= 2 ** 4) {
            y >>= 4;
            z <<= 2;
        }
        if (y >= 2 ** 2) {
            z <<= 1;
        }

        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;

        uint256 zRoundedDown = x / z;
        if (zRoundedDown < z) {
            z = zRoundedDown;
        }
    }

    function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        assembly ("memory-safe") {
            let prod0 := mul(a, b)
            let mm := mulmod(a, b, not(0))
            let prod1 := sub(sub(mm, prod0), lt(mm, prod0))

            if iszero(denominator) {
                revert(0, 0)
            }

            if iszero(prod1) {
                result := div(prod0, denominator)
            }

            if prod1 {
                if iszero(lt(prod1, denominator)) {
                    revert(0, 0)
                }

                let remainder := mulmod(a, b, denominator)

                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)

                let twos := and(sub(0, denominator), denominator)

                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)

                twos := add(div(sub(0, twos), twos), 1)
                prod0 := or(prod0, mul(prod1, twos))

                let inv := xor(mul(3, denominator), 2)

                inv := mul(inv, sub(2, mul(denominator, inv)))
                inv := mul(inv, sub(2, mul(denominator, inv)))
                inv := mul(inv, sub(2, mul(denominator, inv)))
                inv := mul(inv, sub(2, mul(denominator, inv)))
                inv := mul(inv, sub(2, mul(denominator, inv)))
                inv := mul(inv, sub(2, mul(denominator, inv)))

                result := mul(prod0, inv)
            }
        }
    }

    function mulDivSolidity(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256) {
        require(denominator > 0, "MathUtils: zero denom");

        uint256 prod = a * b;

        require(a == 0 || prod / a == b, "MathUtils: overflow");

        return prod / denominator;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256 z) {
        assembly ("memory-safe") {
            z := xor(a, mul(xor(a, b), lt(b, a)))
        }
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256 z) {
        assembly ("memory-safe") {
            z := xor(a, mul(xor(a, b), gt(b, a)))
        }
    }
}
