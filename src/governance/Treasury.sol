// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Treasury is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant TREASURER_ROLE = keccak256("TREASURER_ROLE");

    event EtherReceived(address indexed sender, uint256 amount);
    event EtherWithdrawn(address indexed to, uint256 amount);
    event TokenWithdrawn(address indexed token, address indexed to, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error TransferFailed();

    constructor(address timelockAdmin) {
        if (timelockAdmin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, timelockAdmin);
        _grantRole(TREASURER_ROLE, timelockAdmin);
    }

    receive() external payable {
        emit EtherReceived(msg.sender, msg.value);
    }

    function withdrawEther(address payable to, uint256 amount)
        external
        onlyRole(TREASURER_ROLE)
    {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit EtherWithdrawn(to, amount);
    }

    function withdrawToken(address token, address to, uint256 amount)
        external
        onlyRole(TREASURER_ROLE)
    {
        if (to == address(0) || token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        IERC20(token).safeTransfer(to, amount);
        emit TokenWithdrawn(token, to, amount);
    }

    function ethBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function tokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
