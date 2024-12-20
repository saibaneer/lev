// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;



interface IVault {
    function setCollateralTokenAddress(address _collateralTokenAddress) external;
    function payUser(address _user, uint256 _amount) external;
}