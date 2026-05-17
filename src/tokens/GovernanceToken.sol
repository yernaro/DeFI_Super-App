// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title GovernanceToken
/// @notice ERC20Votes + ERC20Permit governance token, UUPS upgradeable (V1).
///         Mintable by MINTER_ROLE; supply cap enforced by MINTER_ROLE holders.
/// @dev Storage layout must never be reordered between upgrades.
///      V2 may only append new variables after the last existing slot.
contract GovernanceToken is
    Initializable,
    ERC20VotesUpgradeable,
    ERC20PermitUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    // ─────────────────────────────────────────────────────────────────────────
    // Roles
    // ─────────────────────────────────────────────────────────────────────────
    bytes32 public constant MINTER_ROLE   = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // ─────────────────────────────────────────────────────────────────────────
    // Storage — V1 slots (never reorder)
    // ─────────────────────────────────────────────────────────────────────────
    uint256 public maxSupply; // slot 0 after inherited storage

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────
    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────
    error SupplyCapExceeded(uint256 requested, uint256 remaining);
    error ZeroAddress();
    error ZeroAmount();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializer — replaces constructor for UUPS proxies.
    /// @param admin          Receives DEFAULT_ADMIN_ROLE + UPGRADER_ROLE.
    /// @param minter         Receives MINTER_ROLE (typically the Timelock).
    /// @param _maxSupply     Hard cap in token units (wei).
    function initialize(address admin, address minter, uint256 _maxSupply) external initializer {
        if (admin == address(0) || minter == address(0)) revert ZeroAddress();

        __ERC20_init("DeFiSuperApp Governance Token", "DSAT");
        __ERC20Permit_init("DeFiSuperApp Governance Token");
        __ERC20Votes_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        maxSupply = _maxSupply;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE,      admin);
        _grantRole(MINTER_ROLE,        minter);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Minting / Burning
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Mint tokens to `to`. Only MINTER_ROLE.
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        uint256 remaining = maxSupply - totalSupply();
        if (amount > remaining) revert SupplyCapExceeded(amount, remaining);
        _mint(to, amount);
        emit Minted(to, amount);
    }

    /// @notice Burn caller's own tokens.
    function burn(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        _burn(msg.sender, amount);
        emit Burned(msg.sender, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // UUPS upgrade gate
    // ─────────────────────────────────────────────────────────────────────────
    function _authorizeUpgrade(address newImpl) internal override onlyRole(UPGRADER_ROLE) {}

    // ─────────────────────────────────────────────────────────────────────────
    // Required overrides (multiple inheritance resolution)
    // ─────────────────────────────────────────────────────────────────────────
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20PermitUpgradeable, NoncesUpgradeable)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
