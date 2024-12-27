// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;


library StructsLib {
    enum Direction {
        Long,
        Short
    }

    struct MarketCreationParams {
        address priceFeedAddress; // unique identifier
        uint256 assetSize;
        uint256 decimals;
        uint256 maximumLeverage;
    }

    struct LeverageMarket {
        address priceFeedAddress; // unique identifier
        address positionManagerAddress;
        uint256 assetSize;
        uint256 totalLongSize;
        uint256 totalShortSize;
        uint256 decimals;
        uint256 maximumLeverage; // add a minimum leverage
    }

    struct PositionParams {
        uint256 leverage;
        uint256 collateralAmount;
        address positionOwner;
        address priceFeedAddress; // asset address
        Direction longOrShort;
    }

    struct UserPosition {
        address pricefeedAddress;
        uint256 liquidationPrice;
        uint256 entryPrice;
        uint256 leverage;
        uint256 collateral;
        uint256 positionSize; //may be unneccesary
        bytes32 positionId; // unique identifier
        address positionOwner;
        Direction longOrShort;
        uint256 lastUpdatedTime;
        int256 cumulativeFundingValue;
        int256 profitOrLoss;
    }
}

