// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;


interface IOracle {
    function setPrice(uint256 price, address tokenAddress) external;
    function getAssetPrice(address tokenAddress) external  view returns(uint256);
}