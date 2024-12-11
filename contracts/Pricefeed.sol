// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./IPricefeed.sol";

contract Pricefeed is IPricefeed {

    mapping(address => uint256) public tokenPricing;
    function setPrice(uint256 price, address tokenAddress) external {
        tokenPricing[tokenAddress] = price;
    }


    function getAssetPrice(address tokenAddress) external  view returns(uint256) {
        return tokenPricing[tokenAddress];
    }
}