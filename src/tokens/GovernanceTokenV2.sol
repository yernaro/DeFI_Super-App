// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./GovernanceToken.sol";

/// @title GovernanceTokenV2
/// @notice V1 → V2 upgrade: adds a `stakingRewardRate` parameter governed
///         by UPGRADER_ROLE.  All V1 storage slots are preserved at the top;
///         only a new slot is appended.
/// @dev Upgrade path:
///        1. Deploy GovernanceTokenV2 implementation.
///        2. Via Timelock: call upgradeToAndCall(newImpl, abi.encodeCall(initV2, (rate))).
///        3. Verify storage via post-upgrade script.
contract GovernanceTokenV2 is GovernanceToken {
    // ─────────────────────────────────────────────────────────────────────────
    // V2 Storage — appended AFTER all V1 slots (safe: no collision)
    // ─────────────────────────────────────────────────────────────────────────
    uint256 public stakingRewardRate; // basis-points per second
    bool    private _v2Initialized;

    event StakingRewardRateSet(uint256 oldRate, uint256 newRate);

    error AlreadyInitializedV2();

    /// @notice Called via upgradeToAndCall; sets V2-specific state.
    function initV2(uint256 _rate) external onlyRole(UPGRADER_ROLE) {
        if (_v2Initialized) revert AlreadyInitializedV2();
        _v2Initialized = true;
        uint256 old = stakingRewardRate;
        stakingRewardRate = _rate;
        emit StakingRewardRateSet(old, _rate);
    }

    function setStakingRewardRate(uint256 _rate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 old = stakingRewardRate;
        stakingRewardRate = _rate;
        emit StakingRewardRateSet(old, _rate);
    }
}
