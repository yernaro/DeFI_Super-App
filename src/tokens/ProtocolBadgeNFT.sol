// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract ProtocolBadgeNFT is Initializable, ERC721Upgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant MINTER_ROLE   = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    uint256 public maxSupply;
    uint256 public totalMinted;
    string private _baseTokenURI;

    event BadgeMinted(address indexed to, uint256 indexed tokenId);
    event BaseURIUpdated(string baseURI);

    error ZeroAddress();
    error ZeroAmount();
    error MaxSupplyExceeded(uint256 requested, uint256 remaining);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin,
        address minter,
        uint256 _maxSupply,
        string calldata baseURI_
    ) external initializer {
        if (admin == address(0) || minter == address(0)) revert ZeroAddress();
        if (_maxSupply == 0) revert ZeroAmount();

        __ERC721_init("DeFi SuperApp Protocol Badge", "DSAB");
        __AccessControl_init();
        __UUPSUpgradeable_init();

        maxSupply = _maxSupply;
        _baseTokenURI = baseURI_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(MINTER_ROLE, minter);
    }

    function mint(address to) external onlyRole(MINTER_ROLE) returns (uint256) {
        if (to == address(0)) revert ZeroAddress();
        if (totalMinted >= maxSupply) revert MaxSupplyExceeded(1, 0);

        totalMinted += 1;
        uint256 tokenId = totalMinted;
        _safeMint(to, tokenId);

        emit BadgeMinted(to, tokenId);
        return tokenId;
    }

    function setBaseURI(string calldata baseURI_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseTokenURI = baseURI_;
        emit BaseURIUpdated(baseURI_);
    }

    function _authorizeUpgrade(address newImpl) internal override onlyRole(UPGRADER_ROLE) {}

    function supportsInterface(bytes4 interfaceId) public view override(ERC721Upgradeable, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }
}
