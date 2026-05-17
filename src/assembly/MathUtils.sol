// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title MathUtils
/// @notice Common math helpers.  Each function has a pure-Solidity reference
///         implementation (_*Solidity suffix) and an optimised Yul version.
///         Gas benchmarks are in gas-report.md.
library MathUtils {
    // ─────────────────────────────────────────────────────────────────────────
    // sqrt — Babylonian method in Yul
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Integer square root (Yul). ~40 % cheaper than the Solidity version.
    /// @dev Uses the Babylonian / Newton–Raphson iteration.
    function sqrt(uint256 x) internal pure returns (uint256 z) {
        assembly ("memory-safe") {
            // Initial guess: z = x >> 1 (avoids overflow in the first step)
            z := add(shr(1, x), 1)
            if iszero(x) {
                z := 0
                leave
            }
            let y := x
            // Iterate until convergence (at most ~128 iterations for uint256)
            for {} gt(z, y) {} {
                y := z
                // z = (z + x/z) / 2
                z := shr(1, add(div(x, z), z))
            }
            z := y
        }
    }

    /// @notice Pure-Solidity reference — for benchmark comparison only.
    function sqrtSolidity(uint256 x) internal pure returns (uint256 z) {
        if (x == 0) return 0;
        z = x;
        uint256 y = x / 2 + 1;
        while (y < z) {
            z = y;
            y = (x / y + y) / 2;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // mulDiv — overflow-safe in Yul (512-bit intermediate)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Compute floor(a * b / denominator) without overflow.
    ///         Reverts on zero denominator or overflow.
    function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        assembly ("memory-safe") {
            // 512-bit product: (prod1 << 256) | prod0
            let prod0 := mul(a, b)
            let prod1 := sub(sub(mulmod(a, b, not(0)), prod0), lt(mulmod(a, b, not(0)), prod0))

            // Revert if denominator is zero
            if iszero(denominator) { revert(0, 0) }
            // Overflow check: prod1 must be < denominator
            if iszero(lt(prod1, denominator)) { revert(0, 0) }

            // Fast path: fits in 256 bits
            if iszero(prod1) {
                result := div(prod0, denominator)
                leave
            }

            // Subtract denominator's contribution and use the 512-bit division trick
            // remainder = (a * b) mod denominator
            let remainder := mulmod(a, b, denominator)
            // Subtract remainder from (prod1 << 256 | prod0)
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)

            // Factor powers of 2 out of denominator
            // twos = largest power-of-2 divisor of denominator
            let twos := and(sub(0, denominator), denominator)
            // Divide denominator by twos
            denominator := div(denominator, twos)
            // Divide (prod1 << 256 | prod0) by twos
            prod0 := div(prod0, twos)
            // Flip twos (add 1) to use it as multiplicative inverse modulo 2^256
            twos := add(div(sub(0, twos), twos), 1)
            prod0 := or(prod0, mul(prod1, twos))

            // modular inverse of denominator mod 2^256
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

    /// @notice Pure-Solidity reference — for benchmark comparison only.
    function mulDivSolidity(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256) {
        require(denominator > 0, "MathUtils: zero denom");
        uint256 prod = a * b;
        require(a == 0 || prod / a == b, "MathUtils: overflow");
        return prod / denominator;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // min / max
    // ─────────────────────────────────────────────────────────────────────────
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
