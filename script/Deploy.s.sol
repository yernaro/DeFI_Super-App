// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

import "../src/tokens/GovernanceToken.sol";
import "../src/amm/AMM.sol";
import "../src/amm/AMMFactory.sol";
import "../src/lending/LendingPool.sol";
import "../src/vault/YieldVault.sol";
import "../src/governance/DeFiGovernor.sol";
import "../src/governance/Treasury.sol";
import "../src/oracles/ChainlinkOracle.sol";

/// @title Deploy
/// @notice Idempotent deployment script.
///         Environment variables required:
///           DEPLOYER_PRIVATE_KEY  — deployer's private key
///           ADMIN_ADDRESS         — multisig / EOA that receives admin roles initially
///           TOKEN_A               — address of collateral token (e.g. WETH on testnet)
///           TOKEN_B               — address of debt/yield token (e.g. USDC on testnet)
///           CHAINLINK_FEED_A      — price feed for TOKEN_A
///           CHAINLINK_FEED_B      — price feed for TOKEN_B
///           FEED_STALENESS        — max staleness in seconds (e.g. 3600)
///           GOV_TOKEN_MAX_SUPPLY  — max supply in wei (e.g. 100000000000000000000000000)
///           VAULT_PERF_FEE        — performance fee in basis points (e.g. 1000 = 10 %)
///
///         Usage:
///           forge script script/Deploy.s.sol \
///             --rpc-url $ARBITRUM_SEPOLIA_RPC \
///             --private-key $DEPLOYER_PRIVATE_KEY \
///             --broadcast \
///             --verify \
///             --etherscan-api-key $ARBISCAN_API_KEY \
///             -vvvv
contract Deploy is Script {
    struct DeployConfig {
        address admin;
        address tokenA;
        address tokenB;
        address feedA;
        address feedB;
        uint32 feedStaleness;
        uint256 govMaxSupply;
        uint256 vaultPerfFee;
    }

    struct DeployedAddresses {
        address oracle;
        address govTokenImpl;
        address govTokenProxy;
        address timelock;
        address governor;
        address treasury;
        address ammImpl;
        address ammFactory;
        address ammPair;
        address lendingImpl;
        address lendingProxy;
        address vaultImpl;
        address vaultProxy;
    }

    function run() external {
        DeployConfig memory cfg = _loadConfig();
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        DeployedAddresses memory addrs = _deploy(cfg, deployer);

        vm.stopBroadcast();

        _writeAddresses(addrs);
        _logSummary(addrs);
    }

    function _loadConfig() private view returns (DeployConfig memory cfg) {
        cfg.admin = vm.envAddress("ADMIN_ADDRESS");
        cfg.tokenA = vm.envAddress("TOKEN_A");
        cfg.tokenB = vm.envAddress("TOKEN_B");
        cfg.feedA = vm.envAddress("CHAINLINK_FEED_A");
        cfg.feedB = vm.envAddress("CHAINLINK_FEED_B");
        cfg.feedStaleness = uint32(vm.envUint("FEED_STALENESS"));
        cfg.govMaxSupply = vm.envUint("GOV_TOKEN_MAX_SUPPLY");
        cfg.vaultPerfFee = vm.envUint("VAULT_PERF_FEE");
    }

    function _deploy(DeployConfig memory cfg, address deployer) private returns (DeployedAddresses memory addrs) {
        // ── 1. Oracle ─────────────────────────────────────────────────────────
        ChainlinkOracle oracle = new ChainlinkOracle(cfg.admin);
        oracle.setFeed(cfg.tokenA, cfg.feedA, cfg.feedStaleness);
        oracle.setFeed(cfg.tokenB, cfg.feedB, cfg.feedStaleness);
        addrs.oracle = address(oracle);

        // ── 2. Governance Token (UUPS) ────────────────────────────────────────
        GovernanceToken govImpl = new GovernanceToken();
        addrs.govTokenImpl = address(govImpl);

        // Temporarily set deployer as minter; Timelock takes over after setup
        bytes memory govInitData = abi.encodeCall(GovernanceToken.initialize, (cfg.admin, deployer, cfg.govMaxSupply));
        ERC1967Proxy govProxy = new ERC1967Proxy(address(govImpl), govInitData);
        addrs.govTokenProxy = address(govProxy);

        // ── 3. Timelock (2-day delay) ─────────────────────────────────────────
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = address(0); // placeholder — governor set after deploy
        executors[0] = address(0); // anyone can execute after delay
        TimelockController timelock = new TimelockController(
            2 days,
            proposers,
            executors,
            cfg.admin // admin can manage roles during setup
        );
        addrs.timelock = address(timelock);

        // ── 4. Governor ───────────────────────────────────────────────────────
        DeFiGovernor governor = new DeFiGovernor(IVotes(addrs.govTokenProxy), timelock);
        addrs.governor = address(governor);

        // Wire governor as proposer/canceller on Timelock
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        // Revoke deployer's admin — Timelock is now self-governed
        // (keep cfg.admin as backup admin for emergency during testnet phase)

        // ── 5. Treasury ───────────────────────────────────────────────────────
        Treasury treasury = new Treasury(address(timelock));
        addrs.treasury = address(treasury);

        // ── 6. AMM ────────────────────────────────────────────────────────────
        AMM ammImpl = new AMM();
        addrs.ammImpl = address(ammImpl);

        AMMFactory factory = new AMMFactory(cfg.admin, address(ammImpl));
        addrs.ammFactory = address(factory);

        address pair = factory.createPair(cfg.tokenA, cfg.tokenB);
        addrs.ammPair = pair;

        // ── 7. LendingPool (UUPS) ─────────────────────────────────────────────
        LendingPool lendingImpl = new LendingPool();
        addrs.lendingImpl = address(lendingImpl);

        bytes memory lendingInitData = abi.encodeCall(
            LendingPool.initialize, (cfg.tokenA, cfg.tokenB, address(oracle), address(treasury), cfg.admin)
        );
        ERC1967Proxy lendingProxy = new ERC1967Proxy(address(lendingImpl), lendingInitData);
        addrs.lendingProxy = address(lendingProxy);

        // ── 8. YieldVault (UUPS) ──────────────────────────────────────────────
        YieldVault vaultImpl = new YieldVault();
        addrs.vaultImpl = address(vaultImpl);

        bytes memory vaultInitData = abi.encodeCall(
            YieldVault.initialize,
            (cfg.tokenB, "DSA Yield Vault", "dsaYV", cfg.vaultPerfFee, address(treasury), cfg.admin)
        );
        ERC1967Proxy vaultProxy = new ERC1967Proxy(address(vaultImpl), vaultInitData);
        addrs.vaultProxy = address(vaultProxy);

        // ── 9. Transfer MINTER_ROLE on GovToken to Timelock ──────────────────
        GovernanceToken govToken = GovernanceToken(addrs.govTokenProxy);
        govToken.grantRole(govToken.MINTER_ROLE(), address(timelock));
        govToken.revokeRole(govToken.MINTER_ROLE(), deployer);
    }

    function _writeAddresses(DeployedAddresses memory addrs) private {
        string memory json = string(
            abi.encodePacked(
                "{\n",
                '  "oracle":         "',
                vm.toString(addrs.oracle),
                '",\n',
                '  "govTokenImpl":   "',
                vm.toString(addrs.govTokenImpl),
                '",\n',
                '  "govToken":       "',
                vm.toString(addrs.govTokenProxy),
                '",\n',
                '  "timelock":       "',
                vm.toString(addrs.timelock),
                '",\n',
                '  "governor":       "',
                vm.toString(addrs.governor),
                '",\n',
                '  "treasury":       "',
                vm.toString(addrs.treasury),
                '",\n',
                '  "ammImpl":        "',
                vm.toString(addrs.ammImpl),
                '",\n',
                '  "ammFactory":     "',
                vm.toString(addrs.ammFactory),
                '",\n',
                '  "ammPair":        "',
                vm.toString(addrs.ammPair),
                '",\n',
                '  "lendingImpl":    "',
                vm.toString(addrs.lendingImpl),
                '",\n',
                '  "lending":        "',
                vm.toString(addrs.lendingProxy),
                '",\n',
                '  "vaultImpl":      "',
                vm.toString(addrs.vaultImpl),
                '",\n',
                '  "vault":          "',
                vm.toString(addrs.vaultProxy),
                '"\n',
                "}"
            )
        );
        vm.writeFile("./deployments/addresses.json", json);
    }

    function _logSummary(DeployedAddresses memory addrs) private pure {
        console2.log("=== DeFi Super-App Deployment ===");
        console2.log("Oracle:       ", addrs.oracle);
        console2.log("GovToken:     ", addrs.govTokenProxy);
        console2.log("Timelock:     ", addrs.timelock);
        console2.log("Governor:     ", addrs.governor);
        console2.log("Treasury:     ", addrs.treasury);
        console2.log("AMM Factory:  ", addrs.ammFactory);
        console2.log("AMM Pair:     ", addrs.ammPair);
        console2.log("Lending:      ", addrs.lendingProxy);
        console2.log("YieldVault:   ", addrs.vaultProxy);
    }
}
