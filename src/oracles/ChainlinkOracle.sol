// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/// @notice Minimal AggregatorV3Interface (matches Chainlink's on-chain interface).
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @title ChainlinkOracle
/// @notice Oracle adapter with configurable staleness check and role-gated feed updates.
///         Pattern: Oracle Adapter / Interface Abstraction.
contract ChainlinkOracle is AccessControl {
    bytes32 public constant ORACLE_ADMIN = keccak256("ORACLE_ADMIN");

    struct FeedConfig {
        AggregatorV3Interface feed;
        uint32 maxStaleness; // seconds
        uint8  decimals;
    }

    mapping(address token => FeedConfig config) private _feeds;

    event FeedSet(address indexed token, address feed, uint32 maxStaleness);
    event FeedRemoved(address indexed token);

    error FeedNotSet(address token);
    error StalePrice(address token, uint256 updatedAt, uint256 maxStaleness);
    error NegativePrice(address token, int256 price);
    error ZeroPrice(address token);
    error InvalidRound();
    error ZeroAddress();

    constructor(address admin) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ORACLE_ADMIN, admin);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Admin
    // ─────────────────────────────────────────────────────────────────────────

    function setFeed(address token, address feed, uint32 maxStaleness) external onlyRole(ORACLE_ADMIN) {
        if (token == address(0) || feed == address(0)) revert ZeroAddress();
        uint8 dec = AggregatorV3Interface(feed).decimals();
        _feeds[token] = FeedConfig(AggregatorV3Interface(feed), maxStaleness, dec);
        emit FeedSet(token, feed, maxStaleness);
    }

    function removeFeed(address token) external onlyRole(ORACLE_ADMIN) {
        delete _feeds[token];
        emit FeedRemoved(token);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Price reads
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Returns the latest USD price of `token` scaled to 18 decimals.
    function getPrice(address token) external view returns (uint256 price18) {
        FeedConfig storage cfg = _feeds[token];
        if (address(cfg.feed) == address(0)) revert FeedNotSet(token);

        (uint80 roundId, int256 answer, , uint256 updatedAt, uint80 answeredInRound) =
            cfg.feed.latestRoundData();

        // Staleness check
        if (block.timestamp - updatedAt > cfg.maxStaleness) {
            revert StalePrice(token, updatedAt, cfg.maxStaleness);
        }
        // Round validity
        if (answeredInRound < roundId) revert InvalidRound();
        // Sanity checks
        if (answer <= 0) revert NegativePrice(token, answer);

        // Normalise to 18 decimals
        uint256 raw = uint256(answer);
        uint8 dec = cfg.decimals;
        if (dec < 18) {
            price18 = raw * 10 ** (18 - dec);
        } else if (dec > 18) {
            price18 = raw / 10 ** (dec - 18);
        } else {
            price18 = raw;
        }

        if (price18 == 0) revert ZeroPrice(token);
    }

    function getFeedConfig(address token) external view returns (address feed, uint32 maxStaleness, uint8 dec) {
        FeedConfig storage cfg = _feeds[token];
        return (address(cfg.feed), cfg.maxStaleness, cfg.decimals);
    }
}
