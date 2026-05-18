// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../src/oracles/ChainlinkOracle.sol";
import "../../src/amm/AMM.sol";
import "../../src/vault/YieldVault.sol";

contract ForkTest is Test {
    using SafeERC20 for IERC20;

    address constant USDC        = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH        = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC_HOLDER = 0x28C6c06298d514Db089934071355E5743bf21d60;

    address constant ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    function _selectMainnetForkOrSkip() internal {
        string memory rpc = vm.envOr("MAINNET_RPC", string(""));

        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }

        vm.createSelectFork(rpc);
    }

    function test_fork_chainlinkFeedIntegration() public {
        _selectMainnetForkOrSkip();

        address admin = makeAddr("admin");
        ChainlinkOracle oracle = new ChainlinkOracle(admin);

        vm.prank(admin);
        oracle.setFeed(WETH, ETH_USD_FEED, 3600);

        uint256 price = oracle.getPrice(WETH);

        assertGt(price, 100e18, "ETH price too low");
        assertLt(price, 100_000e18, "ETH price too high");

        emit log_named_uint("ETH/USD price (18 dec)", price);
    }

    function test_fork_usdcYieldVault() public {
        _selectMainnetForkOrSkip();

        address admin = makeAddr("admin");
        address treasury = makeAddr("treasury");

        YieldVault vaultImpl = new YieldVault();

        bytes memory initData = abi.encodeCall(
            YieldVault.initialize,
            (USDC, "USDC Yield Vault", "yvUSDC", 500, treasury, admin)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(vaultImpl), initData);
        YieldVault vault = YieldVault(address(proxy));

        uint256 depositAmt = 100_000e6;

        deal(USDC, USDC_HOLDER, depositAmt);

        vm.startPrank(USDC_HOLDER);
        IERC20(USDC).approve(address(vault), depositAmt);
        uint256 shares = vault.deposit(depositAmt, USDC_HOLDER);
        vm.stopPrank();

        assertGt(shares, 0, "No shares minted");
        assertEq(vault.totalAssets(), depositAmt, "totalAssets mismatch");

        vm.prank(USDC_HOLDER);
        uint256 returned = vault.redeem(shares / 2, USDC_HOLDER, USDC_HOLDER);

        assertGt(returned, 0, "No assets returned");

        emit log_named_uint("USDC deposited", depositAmt);
        emit log_named_uint("Shares minted", shares);
        emit log_named_uint("USDC on redeem", returned);
    }

    function test_fork_ammVsUniswapV2PriceComparison() public {
        _selectMainnetForkOrSkip();

        address admin = makeAddr("admin2");

        AMM ammImpl = new AMM();

        bytes memory initData = abi.encodeCall(
            AMM.initialize,
            (USDC, WETH, admin)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(ammImpl), initData);
        AMM localAmm = AMM(address(proxy));

        uint256 usdcAmt = 2_000_000e6;
        uint256 wethAmt = 1000e18;

        deal(USDC, USDC_HOLDER, usdcAmt);
        deal(WETH, USDC_HOLDER, wethAmt);

        vm.startPrank(USDC_HOLDER);

        IERC20(USDC).approve(address(localAmm), usdcAmt);
        IERC20(WETH).approve(address(localAmm), wethAmt);

        localAmm.addLiquidity(usdcAmt, wethAmt, 0, 0);

        uint256 swapIn = 10e18;

        deal(WETH, USDC_HOLDER, wethAmt + swapIn);
        IERC20(WETH).approve(address(localAmm), swapIn);

        (uint112 rA, uint112 rB,) = localAmm.getReserves();

        uint256 quoted = localAmm.getAmountOut(swapIn, rB, rA);
        uint256 actual = localAmm.swap(swapIn, 0, false, USDC_HOLDER);

        vm.stopPrank();

        assertEq(actual, quoted, "Quoted vs actual mismatch");

        uint256 impliedPrice = actual * 1e12 * 1e18 / swapIn;

        emit log_named_uint("WETH in", swapIn);
        emit log_named_uint("USDC out", actual);
        emit log_named_uint("Implied ETH price USD (18dec)", impliedPrice);

        assertGt(impliedPrice, 100e18);
        assertLt(impliedPrice, 100_000e18);
    }
}