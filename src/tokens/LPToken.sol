// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title LPToken
/// @notice ERC-20 LP token minted and burned exclusively by the AMM pair contract.
contract LPToken is ERC20, Ownable {
    constructor(string memory name, string memory symbol, address amm)
        ERC20(name, symbol)
        Ownable(amm)
    {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}
