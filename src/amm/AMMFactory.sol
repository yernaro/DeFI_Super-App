// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./AMM.sol";

/// @title AMMFactory
/// @notice Creates AMM pair proxies using both CREATE (default) and CREATE2
///         (deterministic). Pattern: Factory.
contract AMMFactory is Ownable {
    address public immutable ammImplementation;

    mapping(address => mapping(address => address)) public getPair; // tokenA → tokenB → pair
    address[] public allPairs;

    event PairCreated(address indexed tokenA, address indexed tokenB, address pair, uint256 pairsCount);

    error PairExists(address pair);
    error IdenticalTokens();
    error ZeroAddress();

    constructor(address admin, address _ammImpl) Ownable(admin) {
        if (_ammImpl == address(0)) revert ZeroAddress();
        ammImplementation = _ammImpl;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CREATE — standard nonce-based deployment
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Deploy a new AMM pair for (tokenA, tokenB) using CREATE.
    function createPair(address tokenA, address tokenB) external onlyOwner returns (address pair) {
        (tokenA, tokenB) = _sortTokens(tokenA, tokenB);
        _checkPreCreate(tokenA, tokenB);

        // Deploy proxy pointing at ammImplementation (CREATE)
        bytes memory initData = abi.encodeCall(AMM.initialize, (tokenA, tokenB, owner()));
        pair = address(new ERC1967Proxy(ammImplementation, initData));

        _register(tokenA, tokenB, pair);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CREATE2 — deterministic address
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Deploy a new AMM pair for (tokenA, tokenB) using CREATE2.
    ///         The salt is derived from the token addresses, making the pair
    ///         address predictable before deployment.
    function createPairDeterministic(address tokenA, address tokenB)
        external
        onlyOwner
        returns (address pair)
    {
        (tokenA, tokenB) = _sortTokens(tokenA, tokenB);
        _checkPreCreate(tokenA, tokenB);

        bytes32 salt = keccak256(abi.encodePacked(tokenA, tokenB));
        bytes memory initData = abi.encodeCall(AMM.initialize, (tokenA, tokenB, owner()));

        // CREATE2: deterministic address
        pair = address(new ERC1967Proxy{salt: salt}(ammImplementation, initData));

        _register(tokenA, tokenB, pair);
    }

    /// @notice Predict the address of a CREATE2 pair without deploying it.
    function predictPairAddress(address tokenA, address tokenB) external view returns (address predicted) {
        (tokenA, tokenB) = _sortTokens(tokenA, tokenB);
        bytes32 salt = keccak256(abi.encodePacked(tokenA, tokenB));

        bytes memory proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(ammImplementation, abi.encodeCall(AMM.initialize, (tokenA, tokenB, owner())))
        );

        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(proxyBytecode)));
        predicted = address(uint160(uint256(hash)));
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internals
    // ─────────────────────────────────────────────────────────────────────────
    function _sortTokens(address a, address b) private pure returns (address, address) {
        if (a == address(0) || b == address(0)) revert ZeroAddress();
        if (a == b) revert IdenticalTokens();
        return a < b ? (a, b) : (b, a);
    }

    function _checkPreCreate(address a, address b) private view {
        if (getPair[a][b] != address(0)) revert PairExists(getPair[a][b]);
    }

    function _register(address a, address b, address pair) private {
        getPair[a][b] = pair;
        getPair[b][a] = pair;
        allPairs.push(pair);
        emit PairCreated(a, b, pair, allPairs.length);
    }
}
