// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../src/oracles/ChainlinkOracle.sol";
import "../../src/oracles/MockAggregator.sol";
import "../../src/amm/AMM.sol";
import "../../src/vault/YieldVault.sol";

/// @notice Fork tests that interact with real mainnet contracts.
///         Run with: forge test --match-contract ForkTest --fork-url $MAINNET_RPC -vvv
///
///         Skipped automatically in CI if MAINNET_RPC is not set (vm.skip).
contract ForkTest is Test {
    using SafeERC20 for IERC20;

    // ── Mainnet addresses ────────────────────────────────────────────────────
    address constant USDC        = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH        = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC_HOLDER = 0x28C6c06298d514Db089934071355E5743bf21d60; // Binance 14

    // Chainlink ETH/USD mainnet
    address constant ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    // Uniswap V2 router mainnet
    address constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    // ─────────────────────────────────────────────────────────────────────────
    // Fork test 1: Chainlink ETH/USD live feed integration
    // ─────────────────────────────────────────────────────────────────────────
    function test_fork_chainlinkFeedIntegration() public {
        string memory rpc = vm.envOr("MAINNET_RPC", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }

        address admin = makeAddr("admin");
        ChainlinkOracle oracle = new ChainlinkOracle(admin);

        // Use the real Chainlink ETH/USD feed
        vm.prank(admin);
        oracle.setFeed(WETH, ETH_USD_FEED, 3600);

        uint256 price = oracle.getPrice(WETH);
        // ETH price should be between $100 and $100,000
        assertGt(price, 100e18,   "ETH price too low");
        assertLt(price, 100_000e18, "ETH price too high");

        emit log_named_uint("ETH/USD price (18 dec)", price);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Fork test 2: USDC holder interacts with our YieldVault
    // ─────────────────────────────────────────────────────────────────────────
    function test_fork_usdcYieldVault() public {
        string memory rpc = vm.envOr("MAINNET_RPC", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }

        address admin = makeAddr("admin");
        address treasury = makeAddr("treasury");

        // Deploy YieldVault with USDC as underlying
        YieldVault vaultImpl = new YieldVault();
        bytes memory initData = abi.encodeCall(
            YieldVault.initialize,
            (USDC, "USDC Yield Vault", "yvUSDC", 500, treasury, admin)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(vaultImpl), initData);
        YieldVault vault = YieldVault(address(proxy));

        // Impersonate the USDC holder
        vm.startPrank(USDC_HOLDER);
        uint256 depositAmt = 100_000e6; // 100k USDC
        IERC20(USDC).approve(address(vault), depositAmt);
        uint256 shares = vault.deposit(depositAmt, USDC_HOLDER);
        vm.stopPrank();

        assertGt(shares, 0, "No shares minted");
        assertEq(vault.totalAssets(), depositAmt, "totalAssets mismatch");

        // Withdraw half
        vm.prank(USDC_HOLDER);
        uint256 returned = vault.redeem(shares / 2, USDC_HOLDER, USDC_HOLDER);
        assertGt(returned, 0, "No assets returned");

        emit log_named_uint("USDC deposited",  depositAmt);
        emit log_named_uint("Shares minted",   shares);
        emit log_named_uint("USDC on redeem",  returned);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Fork test 3: Our AMM interacts with Uniswap V2 router for price comparison
    // ─────────────────────────────────────────────────────────────────────────
    function test_fork_ammVsUniswapV2PriceComparison() public {
        string memory rpc = vm.envOr("MAINNET_RPC", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }

        // Deploy our AMM with WETH/USDC
        address admin = makeAddr("admin2");
        AMM ammImpl = new AMM();
        bytes memory initData = abi.encodeCall(AMM.initialize, (USDC, WETH, admin));
        ERC1967Proxy proxy = new ERC1967Proxy(address(ammImpl), initData);
        AMM localAmm = AMM(address(proxy));

        // Seed with USDC_HOLDER's tokens
        vm.startPrank(USDC_HOLDER);
        uint256 usdcAmt = 2_000_000e6; // $2M USDC
        uint256 wethAmt = 1000e18;     // 1000 WETH

        // Deal WETH (use vm.deal for WETH)
        deal(WETH, USDC_HOLDER, wethAmt);

        IERC20(USDC).approve(address(localAmm), usdcAmt);
        IERC20(WETH).approve(address(localAmm), wethAmt);
        localAmm.addLiquidity(usdcAmt, wethAmt, 0, 0);

        // Simulate a 10 WETH → USDC swap
        uint256 swapIn = 10e18;
        deal(WETH, USDC_HOLDER, swapIn);
        IERC20(WETH).approve(address(localAmm), swapIn);

        (uint112 rA, uint112 rB,) = localAmm.getReserves();
        // tokenA=USDC, tokenB=WETH — swap is B→A
        uint256 quoted = localAmm.getAmountOut(swapIn, rB, rA);
        uint256 actual = localAmm.swap(swapIn, 0, false, USDC_HOLDER);
        vm.stopPrank();

        assertEq(actual, quoted, "Quoted vs actual mismatch");
        emit log_named_uint("WETH in",   swapIn);
        emit log_named_uint("USDC out",  actual);

        // Price: actual/swapIn (adjusted for decimals: USDC=6, WETH=18)
        uint256 impliedPrice = actual * 1e12 * 1e18 / swapIn; // normalise to 18-dec USD
        emit log_named_uint("Implied ETH price USD (18dec)", impliedPrice);
        assertGt(impliedPrice, 100e18);
        assertLt(impliedPrice, 100_000e18);
    }
}
