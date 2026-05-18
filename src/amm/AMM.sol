// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../assembly/MathUtils.sol";
import "../tokens/LPToken.sol";

/// @title AMM
/// @notice Constant-product AMM (x · y = k) with:
///           - 0.3 % swap fee sent to LP holders
///           - Slippage protection (minAmountOut)
///           - Reentrancy guard (CEI + ReentrancyGuard)
///           - Pausable circuit breaker (PAUSER_ROLE)
///           - UUPS upgradeable (UPGRADER_ROLE)
/// @dev    Design patterns: Checks-Effects-Interactions, ReentrancyGuard,
///         Pausable / Circuit Breaker, UUPS Proxy.
contract AMM is
    Initializable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────
    uint256 public constant FEE_NUMERATOR   = 3;
    uint256 public constant FEE_DENOMINATOR = 1000; // 0.3 %
    uint256 public constant MINIMUM_LIQUIDITY = 1000; // locked forever

    // ─────────────────────────────────────────────────────────────────────────
    // Roles
    // ─────────────────────────────────────────────────────────────────────────
    bytes32 public constant PAUSER_ROLE   = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // ─────────────────────────────────────────────────────────────────────────
    // Storage — V1 (never reorder; only append for V2+)
    // ─────────────────────────────────────────────────────────────────────────
    IERC20  public tokenA;
    IERC20  public tokenB;
    LPToken public lpToken;

    uint112 private _reserveA;
    uint112 private _reserveB;
    uint32  private _blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast; // k before most recent fee adjustment (for mint fee)

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────
    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpMinted);
    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpBurned);
    event Swap(
        address indexed sender,
        uint256 amountIn,
        uint256 amountOut,
        bool    aToB,
        address indexed recipient
    );
    event Sync(uint112 reserveA, uint112 reserveB);

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────
    error InsufficientLiquidity();
    error InsufficientInputAmount();
    error InsufficientOutputAmount();
    error SlippageExceeded(uint256 amountOut, uint256 minAmountOut);
    error InvalidToken();
    error ZeroAmount();
    error ZeroAddress();
    error Overflow();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    // ─────────────────────────────────────────────────────────────────────────
    // Initializer
    // ─────────────────────────────────────────────────────────────────────────
    function initialize(
        address _tokenA,
        address _tokenB,
        address admin
    ) external initializer {
        if (_tokenA == address(0) || _tokenB == address(0) || admin == address(0)) revert ZeroAddress();
        if (_tokenA == _tokenB) revert InvalidToken();

        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __AccessControl_init();

        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);

        // Deploy LP token owned by this contract
        lpToken = new LPToken(
            string(abi.encodePacked("DSA-LP")),
            string(abi.encodePacked("DSA-LP")),
            address(this)
        );

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE,   admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View helpers
    // ─────────────────────────────────────────────────────────────────────────
    function getReserves() public view returns (uint112 rA, uint112 rB, uint32 ts) {
        rA = _reserveA;
        rB = _reserveB;
        ts = _blockTimestampLast;
    }

    /// @notice Calculate output for a given input using the constant-product formula.
    ///         amountOut = (amountIn * (1 - fee) * reserveOut) / (reserveIn + amountIn * (1 - fee))
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert InsufficientInputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();

        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - FEE_NUMERATOR); // 997
        uint256 numerator       = amountInWithFee * reserveOut;
        uint256 denominator     = reserveIn * FEE_DENOMINATOR + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /// @notice Calculate input required for a specific output.
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256 amountIn)
    {
        if (amountOut == 0) revert InsufficientOutputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        if (amountOut >= reserveOut) revert InsufficientLiquidity();

        uint256 numerator   = reserveIn * amountOut * FEE_DENOMINATOR;
        uint256 denominator = (reserveOut - amountOut) * (FEE_DENOMINATOR - FEE_NUMERATOR);
        amountIn = numerator / denominator + 1;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Add Liquidity
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Deposit tokenA and tokenB to mint LP tokens.
    /// @param amountADesired  Max amount of tokenA to deposit.
    /// @param amountBDesired  Max amount of tokenB to deposit.
    /// @param amountAMin      Slippage protection on tokenA.
    /// @param amountBMin      Slippage protection on tokenB.
    /// @return amountA   Actual tokenA deposited.
    /// @return amountB   Actual tokenB deposited.
    /// @return lp        LP tokens minted.
    function addLiquidity(
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    )
        external
        nonReentrant
        whenNotPaused
        returns (uint256 amountA, uint256 amountB, uint256 lp)
    {
        // ── Checks ──────────────────────────────────────────────────────────
        if (amountADesired == 0 || amountBDesired == 0) revert ZeroAmount();

        (uint112 rA, uint112 rB,) = getReserves();

        if (rA == 0 && rB == 0) {
            amountA = amountADesired;
            amountB = amountBDesired;
        } else {
            uint256 amountBOptimal = _quote(amountADesired, rA, rB);
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin) revert SlippageExceeded(amountBOptimal, amountBMin);
                amountA = amountADesired;
                amountB = amountBOptimal;
            } else {
                uint256 amountAOptimal = _quote(amountBDesired, rB, rA);
                if (amountAOptimal < amountAMin) revert SlippageExceeded(amountAOptimal, amountAMin);
                amountA = amountAOptimal;
                amountB = amountBDesired;
            }
        }

        // ── Effects ─────────────────────────────────────────────────────────
        uint256 totalLP = lpToken.totalSupply();
        if (totalLP == 0) {
            lp = MathUtils.sqrt(amountA * amountB) - MINIMUM_LIQUIDITY;
            lpToken.mint(address(1), MINIMUM_LIQUIDITY); // lock minimum forever
        } else {
            lp = MathUtils.min(amountA * totalLP / rA, amountB * totalLP / rB);
        }
        if (lp == 0) revert InsufficientLiquidity();

        _updateReserves(rA + uint112(amountA), rB + uint112(amountB));

        // ── Interactions ────────────────────────────────────────────────────
        tokenA.safeTransferFrom(msg.sender, address(this), amountA);
        tokenB.safeTransferFrom(msg.sender, address(this), amountB);
        lpToken.mint(msg.sender, lp);

        emit LiquidityAdded(msg.sender, amountA, amountB, lp);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Remove Liquidity
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Burn LP tokens to receive proportional tokenA and tokenB.
    function removeLiquidity(
        uint256 lpAmount,
        uint256 amountAMin,
        uint256 amountBMin
    )
        external
        nonReentrant
        whenNotPaused
        returns (uint256 amountA, uint256 amountB)
    {
        // ── Checks ──────────────────────────────────────────────────────────
        if (lpAmount == 0) revert ZeroAmount();
        (uint112 rA, uint112 rB,) = getReserves();
        uint256 totalLP = lpToken.totalSupply();

        // ── Effects ─────────────────────────────────────────────────────────
        amountA = lpAmount * rA / totalLP;
        amountB = lpAmount * rB / totalLP;
        if (amountA < amountAMin) revert SlippageExceeded(amountA, amountAMin);
        if (amountB < amountBMin) revert SlippageExceeded(amountB, amountBMin);
        if (amountA == 0 || amountB == 0) revert InsufficientLiquidity();

        _updateReserves(rA - uint112(amountA), rB - uint112(amountB));

        // ── Interactions ────────────────────────────────────────────────────
        lpToken.burn(msg.sender, lpAmount);
        tokenA.safeTransfer(msg.sender, amountA);
        tokenB.safeTransfer(msg.sender, amountB);

        emit LiquidityRemoved(msg.sender, amountA, amountB, lpAmount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Swap
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Swap exact amountIn of one token for the other.
    /// @param amountIn    Exact input amount.
    /// @param minAmountOut Minimum output (slippage protection).
    /// @param aToB        Direction: true = tokenA → tokenB; false = tokenB → tokenA.
    /// @param recipient   Recipient of output tokens.
    function swap(
        uint256 amountIn,
        uint256 minAmountOut,
        bool    aToB,
        address recipient
    )
        external
        nonReentrant
        whenNotPaused
        returns (uint256 amountOut)
    {
        // ── Checks ──────────────────────────────────────────────────────────
        if (amountIn == 0) revert InsufficientInputAmount();
        if (recipient == address(0)) revert ZeroAddress();

        (uint112 rA, uint112 rB,) = getReserves();
        (uint256 rIn, uint256 rOut) = aToB ? (uint256(rA), uint256(rB)) : (uint256(rB), uint256(rA));

        amountOut = getAmountOut(amountIn, rIn, rOut);
        if (amountOut < minAmountOut) revert SlippageExceeded(amountOut, minAmountOut);

        // ── Effects ─────────────────────────────────────────────────────────
        if (aToB) {
            _updateReserves(rA + uint112(amountIn), rB - uint112(amountOut));
        } else {
            _updateReserves(rA - uint112(amountOut), rB + uint112(amountIn));
        }

        // ── Interactions ────────────────────────────────────────────────────
        IERC20 tokenIn  = aToB ? tokenA : tokenB;
        IERC20 tokenOut = aToB ? tokenB : tokenA;
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
        tokenOut.safeTransfer(recipient, amountOut);

        emit Swap(msg.sender, amountIn, amountOut, aToB, recipient);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Circuit breaker
    // ─────────────────────────────────────────────────────────────────────────
    function pause()   external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    // ─────────────────────────────────────────────────────────────────────────
    // Internals
    // ─────────────────────────────────────────────────────────────────────────
    function _updateReserves(uint112 rA, uint112 rB) private {
        _reserveA = rA;
        _reserveB = rB;
        _blockTimestampLast = uint32(block.timestamp);
        emit Sync(rA, rB);
    }

    /// @dev Proportional quote: given amount of one token, how much of the other
    ///      at the current reserves ratio?
    function _quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
        private
        pure
        returns (uint256 amountB)
    {
        if (amountA == 0) revert ZeroAmount();
        if (reserveA == 0 || reserveB == 0) revert InsufficientLiquidity();
        amountB = amountA * reserveB / reserveA;
    }

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}
}
