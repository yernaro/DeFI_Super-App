// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./GovernanceToken.sol";

contract GovernanceTokenV2 is GovernanceToken {
    uint256 public stakingRewardRate;
    bool private _v2Initialized;

    event StakingRewardRateSet(uint256 oldRate, uint256 newRate);

    error AlreadyInitializedV2();

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
