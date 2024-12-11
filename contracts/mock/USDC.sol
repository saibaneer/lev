// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract USDC is ERC20, Ownable, ERC20Permit {
    constructor(address initialOwner)
        ERC20("USD Coin", "USDC")
        Ownable(initialOwner)
        ERC20Permit("USD Coin")

    {
        _mint(msg.sender, 50000 * 10 ** 6);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}