// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../oracles/ChainlinkOracle.sol";

contract MockAggregator is AggregatorV3Interface {
    uint8   private _decimals;
    int256  private _answer;
    uint256 private _updatedAt;
    uint80  private _roundId;

    constructor(uint8 dec, int256 initialAnswer) {
        _decimals  = dec;
        _answer    = initialAnswer;
        _updatedAt = block.timestamp;
        _roundId   = 1;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (_roundId, _answer, block.timestamp, _updatedAt, _roundId);
    }

    function setAnswer(int256 answer) external {
        _answer    = answer;
        _updatedAt = block.timestamp;
        _roundId++;
    }

    function setUpdatedAt(uint256 ts) external {
        _updatedAt = ts;
    }

    function setRoundId(uint80 roundId) external {
        _roundId = roundId;
    }
}
