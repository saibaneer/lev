// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IVault.sol";

contract Vault {
    using SafeERC20 for IERC20;

    address public collateralTokenAddress;
    function setCollateralTokenAddress(address _collateralTokenAddress) external {
        collateralTokenAddress = _collateralTokenAddress;
    }
    function payUser(address _user, uint256 _amount) external {
        IERC20 collateralToken = IERC20(collateralTokenAddress);
        collateralToken.safeTransfer(_user, _amount);
    }
}