// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

import "../../src/tokens/GovernanceToken.sol";
import "../../src/tokens/GovernanceTokenV2.sol";
import "../../src/amm/AMM.sol";
import "../../src/amm/AMMFactory.sol";
import "../../src/lending/LendingPool.sol";
import "../../src/vault/YieldVault.sol";
import "../../src/governance/DeFiGovernor.sol";
import "../../src/governance/Treasury.sol";
import "../../src/oracles/ChainlinkOracle.sol";
import "../../src/oracles/MockAggregator.sol";
import "../../src/assembly/MathUtils.sol";

contract MockERC20 is ERC20 {
    uint8 private _dec;

    constructor(string memory n, string memory s, uint8 d) ERC20(n, s) {
        _dec = d;
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

abstract contract BaseTest is Test {
    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal keeper = makeAddr("keeper");

    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    MockERC20 internal tokenC;

    ChainlinkOracle internal oracle;
    MockAggregator internal feedA;
    MockAggregator internal feedB;

    AMM internal ammImpl;
    AMM internal amm;
    AMMFactory internal factory;

    LendingPool internal lendingImpl;
    LendingPool internal lending;

    YieldVault internal vaultImpl;
    YieldVault internal vault;

    GovernanceToken internal govTokenImpl;
    GovernanceToken internal govToken;
    TimelockController internal timelock;
    DeFiGovernor internal governor;
    Treasury internal treasury;

    function setUp() public virtual {
        vm.startPrank(admin);

        tokenA = new MockERC20("TokenA", "TKA", 18);
        tokenB = new MockERC20("TokenB", "TKB", 18);
        tokenC = new MockERC20("TokenC", "TKC", 18);

        oracle = new ChainlinkOracle(admin);
        feedA = new MockAggregator(8, 2000e8);
        feedB = new MockAggregator(8, 1e8);

        oracle.setFeed(address(tokenA), address(feedA), 3600);
        oracle.setFeed(address(tokenB), address(feedB), 3600);

        govTokenImpl = new GovernanceToken();
        bytes memory govInitData = abi.encodeCall(GovernanceToken.initialize, (admin, admin, 100_000_000e18));
        ERC1967Proxy govProxy = new ERC1967Proxy(address(govTokenImpl), govInitData);
        govToken = GovernanceToken(address(govProxy));

        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = address(0);
        executors[0] = address(0);
        timelock = new TimelockController(2 days, proposers, executors, admin);

        governor = new DeFiGovernor(IVotes(address(govToken)), timelock);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        treasury = new Treasury(address(timelock));

        ammImpl = new AMM();
        factory = new AMMFactory(admin, address(ammImpl));

        address ammAddr = factory.createPair(address(tokenA), address(tokenB));
        amm = AMM(ammAddr);

        lendingImpl = new LendingPool();
        bytes memory lendingInit = abi.encodeCall(
            LendingPool.initialize, (address(tokenA), address(tokenB), address(oracle), address(treasury), admin)
        );
        ERC1967Proxy lendingProxy = new ERC1967Proxy(address(lendingImpl), lendingInit);
        lending = LendingPool(address(lendingProxy));

        vaultImpl = new YieldVault();
        bytes memory vaultInit = abi.encodeCall(
            YieldVault.initialize, (address(tokenB), "DSA Yield Vault", "dsaYV", 1000, address(treasury), admin)
        );
        ERC1967Proxy vaultProxy = new ERC1967Proxy(address(vaultImpl), vaultInit);
        vault = YieldVault(address(vaultProxy));

        vault.grantRole(vault.KEEPER_ROLE(), keeper);

        vm.stopPrank();

        _mintAll(alice, 10_000e18, 50_000e18);
        _mintAll(bob, 10_000e18, 50_000e18);
        _mintAll(carol, 10_000e18, 50_000e18);
        _mintAll(keeper, 0, 10_000e18);

        _approveAll(alice);
        _approveAll(bob);
        _approveAll(carol);

        vm.prank(keeper);
        tokenB.approve(address(vault), type(uint256).max);
    }

    function _mintAll(address user, uint256 amtA, uint256 amtB) internal {
        tokenA.mint(user, amtA);
        tokenB.mint(user, amtB);
    }

    function _approveAll(address user) internal {
        vm.startPrank(user);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        tokenA.approve(address(lending), type(uint256).max);
        tokenB.approve(address(lending), type(uint256).max);
        tokenB.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function _addLiquidity(address user, uint256 amtA, uint256 amtB) internal returns (uint256 lp) {
        vm.prank(user);
        (,, lp) = amm.addLiquidity(amtA, amtB, 0, 0);
    }

    function _supplyDebt(address user, uint256 amount) internal {
        vm.prank(user);
        lending.supplyDebtToken(amount);
    }

    function _depositCollateral(address user, uint256 amount) internal {
        vm.prank(user);
        lending.depositCollateral(amount);
    }

    function _borrow(address user, uint256 amount) internal {
        vm.prank(user);
        lending.borrow(amount);
    }
}
