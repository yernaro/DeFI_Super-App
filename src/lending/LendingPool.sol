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

contract LendingPool is
    Initializable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20 for IERC20;

    uint256 public constant PRECISION         = 1e18;
    uint256 public constant LTV               = 75e16;  
    uint256 public constant LIQ_THRESHOLD     = 80e16;  
    uint256 public constant LIQ_BONUS         = 5e16;   
    uint256 public constant BASE_RATE         = 2e16;   
    uint256 public constant SLOPE             = 10e16;  
    uint256 public constant SECONDS_PER_YEAR  = 365 days;
    uint256 public constant PROTOCOL_FEE      = 10e16; 

    bytes32 public constant PAUSER_ROLE   = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant RISK_ADMIN    = keccak256("RISK_ADMIN");

    enum PositionState { None, Active, Liquidated }

    struct Position {
        uint256 collateralAmount; 
        uint256 debtAmount;       
        uint256 interestIndex;    
        PositionState state;
    }

    IERC20          public collateralToken; 
    IERC20          public debtToken;       
    ChainlinkOracle public oracle;
    address         public treasury;

    uint256 public totalCollateral;
    uint256 public totalDebt;
    uint256 public totalReserves; 

    uint256 public cumulativeInterestIndex; 
    uint256 public lastAccrualTimestamp;

    mapping(address => Position) public positions;

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

    error ZeroAmount();
    error ZeroAddress();
    error PositionExists();
    error NoPosition();
    error InsufficientCollateral();
    error ExceedsLTV();
    error HealthyPosition();
    error InsufficientPoolLiquidity();
    error InvalidAmount();

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

        cumulativeInterestIndex = 1e27; 
        lastAccrualTimestamp    = block.timestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE,   admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(RISK_ADMIN,    admin);
    }

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

        cumulativeInterestIndex = cumulativeInterestIndex
            + MathUtils.mulDiv(cumulativeInterestIndex, annualRate * elapsed, SECONDS_PER_YEAR * PRECISION);

        lastAccrualTimestamp = block.timestamp;
        emit InterestAccrued(cumulativeInterestIndex, interest);
    }


    function depositCollateral(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        accrueInterest();

        Position storage pos = positions[msg.sender];
        if (pos.state == PositionState.None) {
            pos.state         = PositionState.Active;
            pos.interestIndex = cumulativeInterestIndex;
        }
        pos.collateralAmount += amount;
        totalCollateral      += amount;

        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        emit CollateralDeposited(msg.sender, amount);
    }


    function withdrawCollateral(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        accrueInterest();
        Position storage pos = positions[msg.sender];
        if (pos.state != PositionState.Active) revert NoPosition();
        if (amount > pos.collateralAmount) revert InsufficientCollateral();

        pos.collateralAmount -= amount;
        totalCollateral      -= amount;

        if (pos.debtAmount > 0 && _healthFactor(pos) < PRECISION) revert InsufficientCollateral();

        collateralToken.safeTransfer(msg.sender, amount);
        emit CollateralWithdrawn(msg.sender, amount);
    }


    function borrow(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        accrueInterest();
        Position storage pos = positions[msg.sender];
        if (pos.state != PositionState.Active) revert NoPosition();
        if (amount > _poolLiquidity()) revert InsufficientPoolLiquidity();

        pos.debtAmount   += amount;
        pos.interestIndex = cumulativeInterestIndex;
        totalDebt        += amount;

        if (_healthFactor(pos) < PRECISION) revert ExceedsLTV();

        debtToken.safeTransfer(msg.sender, amount);
        emit Borrowed(msg.sender, amount);
    }


    function repay(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        accrueInterest();
        Position storage pos = positions[msg.sender];
        if (pos.state != PositionState.Active) revert NoPosition();

        uint256 currentDebt = _currentDebt(pos);
        uint256 repayAmount = amount > currentDebt ? currentDebt : amount;
        uint256 interest    = currentDebt - pos.debtAmount;
        uint256 principal   = repayAmount > interest ? repayAmount - interest : 0;

        pos.debtAmount    = pos.debtAmount > principal ? pos.debtAmount - principal : 0;
        pos.interestIndex = cumulativeInterestIndex;
        totalDebt         = totalDebt > repayAmount ? totalDebt - repayAmount : 0;

        debtToken.safeTransferFrom(msg.sender, address(this), repayAmount);
        emit Repaid(msg.sender, repayAmount, interest);
    }

    function liquidate(address borrower, uint256 debtToRepay) external nonReentrant whenNotPaused {
        if (debtToRepay == 0) revert ZeroAmount();
        accrueInterest();
        Position storage pos = positions[borrower];
        if (pos.state != PositionState.Active) revert NoPosition();
        if (_healthFactor(pos) >= PRECISION)   revert HealthyPosition();

        uint256 currentDebt = _currentDebt(pos);
        uint256 maxRepay = currentDebt / 2 + (currentDebt % 2);
        if (debtToRepay > maxRepay) debtToRepay = maxRepay;

        uint256 collateralPrice = oracle.getPrice(address(collateralToken));
        uint256 debtPrice       = oracle.getPrice(address(debtToken));
        uint256 debtValue       = MathUtils.mulDiv(debtToRepay, debtPrice, PRECISION);
        uint256 collateralSeize = MathUtils.mulDiv(debtValue, PRECISION + LIQ_BONUS, collateralPrice);

        if (collateralSeize > pos.collateralAmount) {
            collateralSeize = pos.collateralAmount;
        }

        pos.collateralAmount -= collateralSeize;
        totalCollateral      -= collateralSeize;

        uint256 principal = debtToRepay > (currentDebt - pos.debtAmount) ? debtToRepay - (currentDebt - pos.debtAmount) : 0;
        pos.debtAmount    = pos.debtAmount > principal ? pos.debtAmount - principal : 0;
        pos.interestIndex = cumulativeInterestIndex;
        totalDebt         = totalDebt > debtToRepay ? totalDebt - debtToRepay : 0;

        if (pos.debtAmount == 0 && pos.collateralAmount == 0) {
            pos.state = PositionState.Liquidated;
        }

        debtToken.safeTransferFrom(msg.sender, address(this), debtToRepay);
        collateralToken.safeTransfer(msg.sender, collateralSeize);
        emit Liquidated(msg.sender, borrower, debtToRepay, collateralSeize);
    }

    function withdrawReserves(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (amount > totalReserves) revert InvalidAmount();
        totalReserves -= amount;
        debtToken.safeTransfer(treasury, amount);
        emit ReservesWithdrawn(treasury, amount);
    }

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

    function supplyDebtToken(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        debtToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    function pause()   external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    function _healthFactor(Position storage pos) private view returns (uint256) {
        if (pos.debtAmount == 0) return type(uint256).max;
        uint256 collateralPrice = oracle.getPrice(address(collateralToken));
        uint256 debtPrice       = oracle.getPrice(address(debtToken));
        uint256 collateralValue = MathUtils.mulDiv(pos.collateralAmount, collateralPrice, PRECISION);
        uint256 debtValue       = MathUtils.mulDiv(_currentDebt(pos), debtPrice, PRECISION);
        uint256 liqThresholdValue = MathUtils.mulDiv(collateralValue, LIQ_THRESHOLD, PRECISION);
        return MathUtils.mulDiv(liqThresholdValue, PRECISION, debtValue);
    }

    function _currentDebt(Position storage pos) private view returns (uint256) {
        if (pos.debtAmount == 0 || pos.interestIndex == 0) return pos.debtAmount;
        return MathUtils.mulDiv(pos.debtAmount, cumulativeInterestIndex, pos.interestIndex);
    }

    function _poolLiquidity() private view returns (uint256) {
        return debtToken.balanceOf(address(this));
    }

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}
}
