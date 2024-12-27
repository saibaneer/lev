// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;



library ErrorLib {
    string constant public UNAUTHORIZED_ACCESS = "Sender != Owner";
    string constant public MAX_COLLATERAL_EXCEEDED = "Max collateral exceeded!";
    string constant public POSITION_DOES_NOT_EXIST = "Position does not exist";
    string constant public PRICE_IS_HIGHER_THAN_CURRENT_ASSET_PRICE = "New liquidation price higher than current asset price";
    string constant public PRICE_IS_LOWER_THAN_CURRENT_ASSET_PRICE= "New liquidation price lower than current asset price";
    string constant public INSUFFICIENT_COLLATERAL = "Insufficient collateral";
    string constant public CANNOT_BE_LIQUIDATED = "Cannot be liquidated";
    // string constant public UNA= "Unauthorized access!";
}