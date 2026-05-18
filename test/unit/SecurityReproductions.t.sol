// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";


contract VulnerableVault {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw() external {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "nothing to withdraw");
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "transfer failed");
        balances[msg.sender] = 0; 
    }
}

contract FixedVault {
    using SafeERC20 for IERC20;

    mapping(address => uint256) public balances;
    bool private _locked;

    error Reentrancy();
    error ZeroBalance();
    error TransferFailed();

    modifier nonReentrant() {
        if (_locked) revert Reentrancy();
        _locked = true;
        _;
        _locked = false;
    }

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw() external nonReentrant {
        uint256 amount = balances[msg.sender];
        if (amount == 0) revert ZeroBalance();
        balances[msg.sender] = 0;
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}

contract ReentrancyAttacker {
    VulnerableVault public target;
    uint256 public stolenAmount;

    constructor(address _target) {
        target = VulnerableVault(_target);
    }

    function attack() external payable {
        target.deposit{value: msg.value}();
        target.withdraw();
    }

    receive() external payable {
        if (address(target).balance >= msg.value && msg.value > 0) {
            stolenAmount += msg.value;
            target.withdraw(); 
        }
    }
}

contract VulnerableProtocol {
    address public owner;
    uint256 public fee;

    constructor() {
        owner = msg.sender;
        fee = 30; 
    }

    function setFee(uint256 newFee) external {
        fee = newFee; 
    }

    function withdrawAll(address to) external {
        (bool ok,) = to.call{value: address(this).balance}("");
        require(ok);
    }

    receive() external payable {}
}

import "@openzeppelin/contracts/access/AccessControl.sol";

contract FixedProtocol is AccessControl {
    bytes32 public constant FEE_SETTER = keccak256("FEE_SETTER");
    bytes32 public constant WITHDRAWER = keccak256("WITHDRAWER");

    uint256 public fee;
    error TransferFailed();

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FEE_SETTER, admin);
        _grantRole(WITHDRAWER, admin);
        fee = 30;
    }

    function setFee(uint256 newFee) external onlyRole(FEE_SETTER) {
        fee = newFee;
    }

    function withdrawAll(address payable to) external onlyRole(WITHDRAWER) {
        uint256 bal = address(this).balance;
        (bool ok,) = to.call{value: bal}("");
        if (!ok) revert TransferFailed();
    }

    receive() external payable {}
}

contract SecurityReproductionTest is Test {
    function test_reentrancy_VULNERABLE_canBeExploited() public {
        VulnerableVault vault = new VulnerableVault();
        address victim = makeAddr("victim");

        vm.deal(victim, 10 ether);
        vm.prank(victim);
        vault.deposit{value: 10 ether}();

        ReentrancyAttacker attacker = new ReentrancyAttacker(address(vault));
        vm.deal(address(attacker), 1 ether);
        attacker.attack{value: 1 ether}();

        assertEq(address(vault).balance, 0);
        assertGt(attacker.stolenAmount(), 1 ether);
    }

    function test_reentrancy_FIXED_preventsExploit() public {
        FixedVault vault = new FixedVault();

        address victim = makeAddr("victim2");
        vm.deal(victim, 10 ether);
        vm.prank(victim);
        vault.deposit{value: 10 ether}();

        address evil = makeAddr("evil");
        vm.deal(evil, 1 ether);
        vm.prank(evil);
        vault.deposit{value: 1 ether}();

        vm.prank(evil);
        vault.withdraw();
        assertEq(vault.balances(evil), 0);

        assertEq(vault.balances(victim), 10 ether);
    }

    function test_accessControl_VULNERABLE_anyoneCanSetFee() public {
        VulnerableProtocol proto = new VulnerableProtocol();
        address attacker = makeAddr("attacker");

        vm.prank(attacker);
        proto.setFee(0);
        assertEq(proto.fee(), 0);
    }

    function test_accessControl_FIXED_blocksUnauthorizedSetFee() public {
        address admin    = makeAddr("admin");
        address attacker = makeAddr("attacker2");
        FixedProtocol proto = new FixedProtocol(admin);

        vm.prank(attacker);
        vm.expectRevert();
        proto.setFee(0);
        assertEq(proto.fee(), 30); 
    }

    function test_accessControl_VULNERABLE_anyoneCanDrain() public {
        VulnerableProtocol proto = new VulnerableProtocol();
        address attacker = makeAddr("attacker3");
        vm.deal(address(proto), 100 ether);

        vm.prank(attacker);
        proto.withdrawAll(attacker);
        assertEq(attacker.balance, 100 ether); 
    }

    function test_accessControl_FIXED_blocksUnauthorizedWithdraw() public {
        address admin    = makeAddr("admin2");
        address attacker = makeAddr("attacker4");
        FixedProtocol proto = new FixedProtocol(admin);
        vm.deal(address(proto), 100 ether);

        vm.prank(attacker);
        vm.expectRevert();
        proto.withdrawAll(payable(attacker));
        assertEq(attacker.balance, 0); 
    }

    function test_accessControl_FIXED_adminCanSetFee() public {
        address admin = makeAddr("admin3");
        FixedProtocol proto = new FixedProtocol(admin);
        vm.prank(admin);
        proto.setFee(50);
        assertEq(proto.fee(), 50);
    }

    function test_accessControl_FIXED_roleTransfer() public {
        address admin = makeAddr("admin4");
        address newFee = makeAddr("newFeeManager");
        FixedProtocol proto = new FixedProtocol(admin);

        bytes32 feeSetterRole = proto.FEE_SETTER();

        vm.prank(admin);
        proto.grantRole(feeSetterRole, newFee);

        vm.prank(newFee);
        proto.setFee(10);

        assertEq(proto.fee(), 10);
    }
}
