// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../assembly/MathUtils.sol";

contract YieldVault is
    Initializable,
    ERC4626Upgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 public constant KEEPER_ROLE   = keccak256("KEEPER_ROLE");
    bytes32 public constant PAUSER_ROLE   = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    uint256 public totalHarvested;
    uint256 public performanceFee; 
    address public feeRecipient;

    uint256 private constant VIRTUAL_SHARES = 1e3;
    uint256 private constant VIRTUAL_ASSETS = 1;

    event YieldHarvested(uint256 amount, uint256 fee, address feeRecipient);
    event PerformanceFeeSet(uint256 oldFee, uint256 newFee);
    event FeeRecipientSet(address oldRecipient, address newRecipient);

    error ZeroAmount();
    error ZeroAddress();
    error FeeTooHigh();

    constructor() { _disableInitializers(); }

    function initialize(
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _performanceFee,
        address _feeRecipient,
        address admin
    ) external initializer {
        if (_asset == address(0) || _feeRecipient == address(0) || admin == address(0)) revert ZeroAddress();
        if (_performanceFee > 3000) revert FeeTooHigh(); 

        __ERC4626_init(IERC20(_asset));
        __ERC20_init(_name, _symbol);
        __ReentrancyGuard_init();
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        performanceFee = _performanceFee;
        feeRecipient   = _feeRecipient;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(KEEPER_ROLE,   admin);
        _grantRole(PAUSER_ROLE,   admin);
        _grantRole(UPGRADER_ROLE, admin);
    }


    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    function _convertToShares(uint256 assets, Math.Rounding rounding)
        internal
        view
        override
        returns (uint256)
    {
        return MathUtils.mulDiv(
            assets,
            totalSupply() + VIRTUAL_SHARES,
            totalAssets() + VIRTUAL_ASSETS + (rounding == Math.Rounding.Ceil ? 1 : 0)
        );
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding)
        internal
        view
        override
        returns (uint256)
    {
        return MathUtils.mulDiv(
            shares,
            totalAssets() + VIRTUAL_ASSETS,
            totalSupply() + VIRTUAL_SHARES + (rounding == Math.Rounding.Ceil ? 1 : 0)
        );
    }


    function deposit(uint256 assets, address receiver)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        if (assets == 0) revert ZeroAmount();
        return super.deposit(assets, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner_)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        if (assets == 0) revert ZeroAmount();
        return super.withdraw(assets, receiver, owner_);
    }

    function mint(uint256 shares, address receiver)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        if (shares == 0) revert ZeroAmount();
        return super.mint(shares, receiver);
    }

    function redeem(uint256 shares, address receiver, address owner_)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        if (shares == 0) revert ZeroAmount();
        return super.redeem(shares, receiver, owner_);
    }


    function harvestYield(uint256 amount) external onlyRole(KEEPER_ROLE) nonReentrant {
        if (amount == 0) revert ZeroAmount();

        uint256 fee = MathUtils.mulDiv(amount, performanceFee, 10_000);
        uint256 net = amount - fee;

        totalHarvested += net;

        if (fee > 0) {
            IERC20(asset()).safeTransferFrom(msg.sender, feeRecipient, fee);
        }
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), net);

        emit YieldHarvested(amount, fee, feeRecipient);
    }

    function setPerformanceFee(uint256 fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (fee > 3000) revert FeeTooHigh();
        emit PerformanceFeeSet(performanceFee, fee);
        performanceFee = fee;
    }

    function setFeeRecipient(address recipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (recipient == address(0)) revert ZeroAddress();
        emit FeeRecipientSet(feeRecipient, recipient);
        feeRecipient = recipient;
    }

    function pause()   external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}
}
