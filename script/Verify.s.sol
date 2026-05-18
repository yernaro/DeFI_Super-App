// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "../src/tokens/GovernanceToken.sol";
import "../src/governance/DeFiGovernor.sol";
import "../src/governance/Treasury.sol";
import "../src/lending/LendingPool.sol";
import "../src/vault/YieldVault.sol";
import "../src/amm/AMM.sol";
import "../src/oracles/ChainlinkOracle.sol";

contract Verify is Script {
    uint256 constant EXPECTED_TIMELOCK_DELAY = 2 days;
    uint256 constant EXPECTED_VOTING_DELAY = 1 days;
    uint256 constant EXPECTED_VOTING_PERIOD = 1 weeks;
    uint256 constant EXPECTED_QUORUM_PCT = 4;

    bool private _allPassed = true;

    function run() external {
        string memory raw = vm.readFile("./deployments/addresses.json");

        address oracle = vm.parseJsonAddress(raw, ".oracle");
        address govToken = vm.parseJsonAddress(raw, ".govToken");
        address timelockAddr = vm.parseJsonAddress(raw, ".timelock");
        address governorAddr = vm.parseJsonAddress(raw, ".governor");
        address treasuryAddr = vm.parseJsonAddress(raw, ".treasury");
        address lendingAddr = vm.parseJsonAddress(raw, ".lending");
        address vaultAddr = vm.parseJsonAddress(raw, ".vault");
        address ammPair = vm.parseJsonAddress(raw, ".ammPair");

        TimelockController timelock = TimelockController(payable(timelockAddr));
        DeFiGovernor governor = DeFiGovernor(payable(governorAddr));
        GovernanceToken token = GovernanceToken(govToken);

        console2.log("\n========== POST-DEPLOYMENT VERIFICATION ==========\n");

        _check("Timelock minimum delay == 2 days", timelock.getMinDelay() == EXPECTED_TIMELOCK_DELAY);

        _check("Governor votingDelay == 1 day", governor.votingDelay() == EXPECTED_VOTING_DELAY);

        _check("Governor votingPeriod == 1 week", governor.votingPeriod() == EXPECTED_VOTING_PERIOD);

        _check("Governor quorumNumerator == 4%", governor.quorumNumerator() == EXPECTED_QUORUM_PCT);

        _check("Governor token == GovToken", address(governor.token()) == govToken);

        _check("Governor has PROPOSER_ROLE on Timelock", timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)));

        _check(
            "Governor has CANCELLER_ROLE on Timelock", timelock.hasRole(timelock.CANCELLER_ROLE(), address(governor))
        );

        bytes32 minterRole = token.MINTER_ROLE();

        _check("Timelock has MINTER_ROLE on GovToken", token.hasRole(minterRole, timelockAddr));

        _check("Treasury is deployed", treasuryAddr != address(0));

        LendingPool lending = LendingPool(lendingAddr);
        bytes32 lendingAdminRole = lending.DEFAULT_ADMIN_ROLE();

        console2.log("[INFO] LendingPool deployer has admin role:", lending.hasRole(lendingAdminRole, msg.sender));

        YieldVault vault = YieldVault(vaultAddr);
        bytes32 vaultAdminRole = vault.DEFAULT_ADMIN_ROLE();

        console2.log("[INFO] YieldVault deployer has admin role:", vault.hasRole(vaultAdminRole, msg.sender));

        (uint112 rA, uint112 rB,) = AMM(ammPair).getReserves();
        console2.log("[INFO] AMM reserve A:", rA);
        console2.log("[INFO] AMM reserve B:", rB);

        console2.log("[INFO] Oracle deployed at:", oracle);

        console2.log("\n==================================================");

        if (_allPassed) {
            console2.log("ALL CHECKS PASSED");
        } else {
            console2.log("ONE OR MORE CHECKS FAILED - review output above");
            revert("Verification failed");
        }
    }

    function _check(string memory label, bool condition) private {
        if (condition) {
            console2.log("[PASS]", label);
        } else {
            console2.log("[FAIL]", label);
            _allPassed = false;
        }
    }
}
