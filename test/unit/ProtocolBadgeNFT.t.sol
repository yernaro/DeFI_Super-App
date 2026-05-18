// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/tokens/ProtocolBadgeNFT.sol";

contract ProtocolBadgeNFTTest is Test {
    ProtocolBadgeNFT badge;

    address admin = address(0xA11CE);
    address minter = address(0xB0B);
    address alice = address(0xCAFE);
    address bob = address(0xBEEF);

    function setUp() public {
        ProtocolBadgeNFT impl = new ProtocolBadgeNFT();

        bytes memory data = abi.encodeCall(
            ProtocolBadgeNFT.initialize,
            (admin, minter, 3, "ipfs://badge/")
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        badge = ProtocolBadgeNFT(address(proxy));
    }

    function test_initialize_success() public view {
        assertEq(badge.name(), "DeFi SuperApp Protocol Badge");
        assertEq(badge.symbol(), "DSAB");
        assertEq(badge.maxSupply(), 3);
        assertEq(badge.totalMinted(), 0);

        assertTrue(badge.hasRole(badge.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(badge.hasRole(badge.MINTER_ROLE(), minter));
        assertTrue(badge.hasRole(badge.UPGRADER_ROLE(), admin));
    }

    function test_initialize_reverts_zeroAdmin() public {
        ProtocolBadgeNFT impl = new ProtocolBadgeNFT();

        bytes memory data = abi.encodeCall(
            ProtocolBadgeNFT.initialize,
            (address(0), minter, 3, "ipfs://badge/")
        );

        vm.expectRevert(ProtocolBadgeNFT.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function test_initialize_reverts_zeroMinter() public {
        ProtocolBadgeNFT impl = new ProtocolBadgeNFT();

        bytes memory data = abi.encodeCall(
            ProtocolBadgeNFT.initialize,
            (admin, address(0), 3, "ipfs://badge/")
        );

        vm.expectRevert(ProtocolBadgeNFT.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function test_initialize_reverts_zeroMaxSupply() public {
        ProtocolBadgeNFT impl = new ProtocolBadgeNFT();

        bytes memory data = abi.encodeCall(
            ProtocolBadgeNFT.initialize,
            (admin, minter, 0, "ipfs://badge/")
        );

        vm.expectRevert(ProtocolBadgeNFT.ZeroAmount.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function test_mint_success() public {
        vm.prank(minter);
        uint256 tokenId = badge.mint(alice);

        assertEq(tokenId, 1);
        assertEq(badge.ownerOf(1), alice);
        assertEq(badge.totalMinted(), 1);
        assertEq(badge.tokenURI(1), "ipfs://badge/1");
    }

    function test_mint_onlyMinter() public {
        vm.prank(alice);
        vm.expectRevert();
        badge.mint(alice);
    }

    function test_mint_reverts_zeroAddress() public {
        vm.prank(minter);
        vm.expectRevert(ProtocolBadgeNFT.ZeroAddress.selector);
        badge.mint(address(0));
    }

    function test_mint_reverts_maxSupplyExceeded() public {
        vm.startPrank(minter);

        badge.mint(alice);
        badge.mint(bob);
        badge.mint(address(0x1234));

        vm.expectRevert(
            abi.encodeWithSelector(
                ProtocolBadgeNFT.MaxSupplyExceeded.selector,
                1,
                0
            )
        );
        badge.mint(address(0x5678));

        vm.stopPrank();
    }

    function test_setBaseURI_success() public {
        vm.prank(admin);
        badge.setBaseURI("ipfs://new/");

        vm.prank(minter);
        badge.mint(alice);

        assertEq(badge.tokenURI(1), "ipfs://new/1");
    }

    function test_setBaseURI_onlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        badge.setBaseURI("ipfs://hack/");
    }

    function test_supportsInterface() public view {
        assertTrue(badge.supportsInterface(0x80ac58cd));
        assertTrue(badge.supportsInterface(0x01ffc9a7));
    }

    function test_upgrade_onlyUpgrader() public {
        ProtocolBadgeNFT newImpl = new ProtocolBadgeNFT();

        vm.prank(alice);
        vm.expectRevert();
        badge.upgradeToAndCall(address(newImpl), "");
    }

    function test_upgrade_byAdmin() public {
        ProtocolBadgeNFT newImpl = new ProtocolBadgeNFT();

        vm.prank(admin);
        badge.upgradeToAndCall(address(newImpl), "");
    }

    function test_tokenURI_reverts_forNonexistentToken() public {
        vm.expectRevert();
        badge.tokenURI(999);
    }

    function test_mint_emitsBadgeMintedEvent() public {
        vm.expectEmit(true, true, false, false);
        emit ProtocolBadgeNFT.BadgeMinted(alice, 1);

        vm.prank(minter);
        badge.mint(alice);
    }
}

