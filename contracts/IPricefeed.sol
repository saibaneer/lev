// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;


interface IPricefeed {
    function setPrice(uint256 price, address tokenAddress) external;
}