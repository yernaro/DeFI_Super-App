// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../oracles/ChainlinkOracle.sol";
import "../assembly/MathUtils.sol";

/// @title LendingPool
/// @notice Single-asset collateral lending pool.
///         - Users deposit tokenA as collateral.
///         - Users borrow tokenB against collateral (LTV-gated).
///         - Linear interest rate model: baseRate + utilizationRate * slope.
///         - Liquidation when healthFactor < 1e18.
///         - Fees accrue to protocol treasury.
///         - UUPS upgradeable, Pausable circuit-breaker.
/// @dev    Design patterns: Checks-Effects-Interactions, ReentrancyGuard,
///         Pausable, UUPS, State Machine (position lifecycle), AccessControl.
contract LendingPool is
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
    uint256 public constant PRECISION         = 1e18;
    uint256 public constant LTV               = 75e16;  // 75 % (1e18 = 100 %)
    uint256 public constant LIQ_THRESHOLD     = 80e16;  // 80 %
    uint256 public constant LIQ_BONUS         = 5e16;   // 5 % bonus to liquidator
    uint256 public constant BASE_RATE         = 2e16;   // 2 % per year
    uint256 public constant SLOPE             = 10e16;  // 10 % per year at 100 % util
    uint256 public constant SECONDS_PER_YEAR  = 365 days;
    uint256 public constant PROTOCOL_FEE      = 10e16; // 10 % of interest to treasury

    // ─────────────────────────────────────────────────────────────────────────
    // Roles
    // ─────────────────────────────────────────────────────────────────────────
    bytes32 public constant PAUSER_ROLE   = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant RISK_ADMIN    = keccak256("RISK_ADMIN");

    // ─────────────────────────────────────────────────────────────────────────
    // Position state machine
    // ─────────────────────────────────────────────────────────────────────────
    enum PositionState { None, Active, Liquidated }

    struct Position {
        uint256 collateralAmount; // tokenA deposited
        uint256 debtAmount;       // tokenB borrowed (principal)
        uint256 interestIndex;    // snapshot of cumulativeInterestIndex at last action
        PositionState state;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Storage — V1
    // ─────────────────────────────────────────────────────────────────────────
    IERC20          public collateralToken; // tokenA
    IERC20          public debtToken;       // tokenB
    ChainlinkOracle public oracle;
    address         public treasury;

    uint256 public totalCollateral;
    uint256 public totalDebt;
    uint256 public totalReserves; // protocol fee accrual

    uint256 public cumulativeInterestIndex; // ray (1e27 = 1.0)
    uint256 public lastAccrualTimestamp;

    mapping(address => Position) public positions;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────
    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount, uint256 interest);
    event Liquidated(
        address indexed liquidator,
        address indexed borrower,
        uint256 debtRepaid,
        uint256 collateralSeized
    );
    event InterestAccrued(uint256 newIndex, uint256 interestAccrued);
    event ReservesWithdrawn(address indexed treasury, uint256 amount);

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────
    error ZeroAmount();
    error ZeroAddress();
    error PositionExists();
    error NoPosition();
    error InsufficientCollateral();
    error ExceedsLTV();
    error HealthyPosition();
    error InsufficientPoolLiquidity();
    error InvalidAmount();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(
        address _collateralToken,
        address _debtToken,
        address _oracle,
        address _treasury,
        address admin
    ) external initializer {
        if (_collateralToken == address(0) || _debtToken == address(0)
            || _oracle == address(0) || _treasury == address(0) || admin == address(0))
        {
            revert ZeroAddress();
        }

        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __AccessControl_init();

        collateralToken = IERC20(_collateralToken);
        debtToken       = IERC20(_debtToken);
        oracle          = ChainlinkOracle(_oracle);
        treasury        = _treasury;

        cumulativeInterestIndex = 1e27; // RAY = 1.0
        lastAccrualTimestamp    = block.timestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE,   admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(RISK_ADMIN,    admin);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Interest accrual
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Accrue interest since last interaction. Called at the start of
    ///         every state-changing function.
    function accrueInterest() public {
        uint256 elapsed = block.timestamp - lastAccrualTimestamp;
        if (elapsed == 0) return;

        uint256 utilization = totalDebt == 0 ? 0 : totalDebt * PRECISION / (totalDebt + _poolLiquidity());
        uint256 annualRate  = BASE_RATE + MathUtils.mulDiv(SLOPE, utilization, PRECISION);
        uint256 interest    = MathUtils.mulDiv(totalDebt, annualRate * elapsed, SECONDS_PER_YEAR * PRECISION);

        if (interest == 0) {
            lastAccrualTimestamp = block.timestamp;
            return;
        }

        uint256 protocolCut = MathUtils.mulDiv(interest, PROTOCOL_FEE, PRECISION);
        totalReserves += protocolCut;
        totalDebt     += interest;

        // Update cumulative index: newIndex = oldIndex * (1 + rate * dt)
        cumulativeInterestIndex = cumulativeInterestIndex
            + MathUtils.mulDiv(cumulativeInterestIndex, annualRate * elapsed, SECONDS_PER_YEAR * PRECISION);

        lastAccrualTimestamp = block.timestamp;
        emit InterestAccrued(cumulativeInterestIndex, interest);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Deposit collateral
    // ─────────────────────────────────────────────────────────────────────────

    function depositCollateral(uint256 amount) external nonReentrant whenNotPaused {
        // ── Checks ──────────────────────────────────────────────────────────
        if (amount == 0) revert ZeroAmount();
        accrueInterest();

        // ── Effects ─────────────────────────────────────────────────────────
        Position storage pos = positions[msg.sender];
        if (pos.state == PositionState.None) {
            pos.state         = PositionState.Active;
            pos.interestIndex = cumulativeInterestIndex;
        }
        pos.collateralAmount += amount;
        totalCollateral      += amount;

        // ── Interactions ────────────────────────────────────────────────────
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        emit CollateralDeposited(msg.sender, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Withdraw collateral
    // ─────────────────────────────────────────────────────────────────────────

    function withdrawCollateral(uint256 amount) external nonReentrant whenNotPaused {
        // ── Checks ──────────────────────────────────────────────────────────
        if (amount == 0) revert ZeroAmount();
        accrueInterest();
        Position storage pos = positions[msg.sender];
        if (pos.state != PositionState.Active) revert NoPosition();
        if (amount > pos.collateralAmount) revert InsufficientCollateral();

        // ── Effects ─────────────────────────────────────────────────────────
        pos.collateralAmount -= amount;
        totalCollateral      -= amount;

        // Check health after withdrawal
        if (pos.debtAmount > 0 && _healthFactor(pos) < PRECISION) revert InsufficientCollateral();

        // ── Interactions ────────────────────────────────────────────────────
        collateralToken.safeTransfer(msg.sender, amount);
        emit CollateralWithdrawn(msg.sender, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Borrow
    // ─────────────────────────────────────────────────────────────────────────

    function borrow(uint256 amount) external nonReentrant whenNotPaused {
        // ── Checks ──────────────────────────────────────────────────────────
        if (amount == 0) revert ZeroAmount();
        accrueInterest();
        Position storage pos = positions[msg.sender];
        if (pos.state != PositionState.Active) revert NoPosition();
        if (amount > _poolLiquidity()) revert InsufficientPoolLiquidity();

        // ── Effects ─────────────────────────────────────────────────────────
        pos.debtAmount   += amount;
        pos.interestIndex = cumulativeInterestIndex;
        totalDebt        += amount;

        if (_healthFactor(pos) < PRECISION) revert ExceedsLTV();

        // ── Interactions ────────────────────────────────────────────────────
        debtToken.safeTransfer(msg.sender, amount);
        emit Borrowed(msg.sender, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Repay
    // ─────────────────────────────────────────────────────────────────────────

    function repay(uint256 amount) external nonReentrant whenNotPaused {
        // ── Checks ──────────────────────────────────────────────────────────
        if (amount == 0) revert ZeroAmount();
        accrueInterest();
        Position storage pos = positions[msg.sender];
        if (pos.state != PositionState.Active) revert NoPosition();

        // ── Effects ─────────────────────────────────────────────────────────
        uint256 currentDebt = _currentDebt(pos);
        uint256 repayAmount = amount > currentDebt ? currentDebt : amount;
        uint256 interest    = currentDebt - pos.debtAmount;
        uint256 principal   = repayAmount > interest ? repayAmount - interest : 0;

        pos.debtAmount    = pos.debtAmount > principal ? pos.debtAmount - principal : 0;
        pos.interestIndex = cumulativeInterestIndex;
        totalDebt         = totalDebt > repayAmount ? totalDebt - repayAmount : 0;

        // ── Interactions ────────────────────────────────────────────────────
        debtToken.safeTransferFrom(msg.sender, address(this), repayAmount);
        emit Repaid(msg.sender, repayAmount, interest);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Liquidation
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Liquidate an unhealthy position.
    ///         Liquidator repays up to 50 % of borrower's debt and receives
    ///         collateral + LIQ_BONUS.
    function liquidate(address borrower, uint256 debtToRepay) external nonReentrant whenNotPaused {
        // ── Checks ──────────────────────────────────────────────────────────
        if (debtToRepay == 0) revert ZeroAmount();
        accrueInterest();
        Position storage pos = positions[borrower];
        if (pos.state != PositionState.Active) revert NoPosition();
        if (_healthFactor(pos) >= PRECISION)   revert HealthyPosition();

        uint256 currentDebt = _currentDebt(pos);
        // Max 50 % close factor
        uint256 maxRepay = currentDebt / 2 + (currentDebt % 2);
        if (debtToRepay > maxRepay) debtToRepay = maxRepay;

        // Collateral to seize: (debtRepaid in collateral terms) * (1 + bonus)
        uint256 collateralPrice = oracle.getPrice(address(collateralToken));
        uint256 debtPrice       = oracle.getPrice(address(debtToken));
        uint256 debtValue       = MathUtils.mulDiv(debtToRepay, debtPrice, PRECISION);
        uint256 collateralSeize = MathUtils.mulDiv(debtValue, PRECISION + LIQ_BONUS, collateralPrice);

        if (collateralSeize > pos.collateralAmount) {
            collateralSeize = pos.collateralAmount;
        }

        // ── Effects ─────────────────────────────────────────────────────────
        pos.collateralAmount -= collateralSeize;
        totalCollateral      -= collateralSeize;

        uint256 principal = debtToRepay > (currentDebt - pos.debtAmount) ? debtToRepay - (currentDebt - pos.debtAmount) : 0;
        pos.debtAmount    = pos.debtAmount > principal ? pos.debtAmount - principal : 0;
        pos.interestIndex = cumulativeInterestIndex;
        totalDebt         = totalDebt > debtToRepay ? totalDebt - debtToRepay : 0;

        if (pos.debtAmount == 0 && pos.collateralAmount == 0) {
            pos.state = PositionState.Liquidated;
        }

        // ── Interactions ────────────────────────────────────────────────────
        debtToken.safeTransferFrom(msg.sender, address(this), debtToRepay);
        collateralToken.safeTransfer(msg.sender, collateralSeize);
        emit Liquidated(msg.sender, borrower, debtToRepay, collateralSeize);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Protocol reserves withdrawal (Timelock/treasury)
    // ─────────────────────────────────────────────────────────────────────────
    function withdrawReserves(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (amount > totalReserves) revert InvalidAmount();
        totalReserves -= amount;
        debtToken.safeTransfer(treasury, amount);
        emit ReservesWithdrawn(treasury, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View helpers
    // ─────────────────────────────────────────────────────────────────────────
    function healthFactor(address user) external view returns (uint256) {
        return _healthFactor(positions[user]);
    }

    function currentDebt(address user) external view returns (uint256) {
        return _currentDebt(positions[user]);
    }

    function utilizationRate() external view returns (uint256) {
        uint256 liquidity = _poolLiquidity();
        if (totalDebt == 0) return 0;
        return totalDebt * PRECISION / (totalDebt + liquidity);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Provide debt liquidity (supply-side, simplified)
    // ─────────────────────────────────────────────────────────────────────────
    function supplyDebtToken(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        debtToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Circuit breaker
    // ─────────────────────────────────────────────────────────────────────────
    function pause()   external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    // ─────────────────────────────────────────────────────────────────────────
    // Internals
    // ─────────────────────────────────────────────────────────────────────────
    function _healthFactor(Position storage pos) private view returns (uint256) {
        if (pos.debtAmount == 0) return type(uint256).max;
        uint256 collateralPrice = oracle.getPrice(address(collateralToken));
        uint256 debtPrice       = oracle.getPrice(address(debtToken));
        uint256 collateralValue = MathUtils.mulDiv(pos.collateralAmount, collateralPrice, PRECISION);
        uint256 debtValue       = MathUtils.mulDiv(_currentDebt(pos), debtPrice, PRECISION);
        uint256 liqThresholdValue = MathUtils.mulDiv(collateralValue, LIQ_THRESHOLD, PRECISION);
        return MathUtils.mulDiv(liqThresholdValue, PRECISION, debtValue);
    }

    /// @dev Applies accrued interest to position's snapshot debt.
    function _currentDebt(Position storage pos) private view returns (uint256) {
        if (pos.debtAmount == 0 || pos.interestIndex == 0) return pos.debtAmount;
        return MathUtils.mulDiv(pos.debtAmount, cumulativeInterestIndex, pos.interestIndex);
    }

    function _poolLiquidity() private view returns (uint256) {
        return debtToken.balanceOf(address(this));
    }

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}
}
