// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./IOracle.sol";

contract Oracle is IOracle {

    mapping(address => uint256) public tokenPricing;
    function setPrice(uint256 price, address tokenAddress) external {
        tokenPricing[tokenAddress] = price;
    }


    function getAssetPrice(address tokenAddress) external view returns(uint256) {
        return tokenPricing[tokenAddress];
    }
}