// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;


library ConstantsLib {
    uint256 constant public MIN_POSITION_SIZE = 100e8;
    uint256 constant public MIN_PRICE = 100e10;
    uint256 constant public MIN_P_N_L = 100e10;
    uint256 constant public MAX_LEVERAGE = 100;
    uint256 constant public MAXIMUM_COLLATERAL = 10000e18;
    uint256 constant public LIQUIDATION_FEE_PERCENTAGE = 5;
    uint256 constant public TRADING_FEE_PERCENTAGE = 5;
    uint256 constant public MINIMUM_TRADE_SIZE = 10e18;
}