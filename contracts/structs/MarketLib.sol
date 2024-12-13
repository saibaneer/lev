// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library MarketLib {
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
        uint256 assetSize;
        uint256 totalLongSize;
        uint256 totalShortSize;
        uint256 decimals;
        uint256 maximumLeverage; // add a minimum leverage
    }

    // struct AUM {

    // }

    struct PositionParams {
        uint256 entryPrice;
        uint256 leverage;
        uint256 collateralAmount;
        address positionOwner;
        address priceFeedAddress; // asset address
        Direction longOrShort;
    }

    struct UserPosition {
        uint256 liquidationPrice;
        uint256 entryPrice;
        uint256 leverage;
        uint256 collateral;
        uint256 positionSize; //may be unneccesary
        bytes32 positionId; // unique identifier
        address positionOwner;
        // address priceFeedAddress; // asset address
        Direction longOrShort;
        uint256 lastUpdatedTime;
    }

    function id(
        address positionOwner,
        uint256 userNonce
    ) internal pure returns (bytes32) {
        bytes32 positionId = keccak256(
            abi.encodePacked(positionOwner, userNonce)
        );
        return positionId;
    }

    function estimatePositionSize(
        uint256 leverage,
        uint256 collateral
    ) internal pure returns (uint256) {
        return leverage * collateral;
    }

    function estimateLiquidationPrice(
        uint256 entryPrice,
        uint256 leverage,
        uint256 collateral,
        uint256 maintenanceMargin,
        Direction longOrShort
    ) internal pure returns (uint256) {
        uint256 positionSize = estimatePositionSize(leverage, collateral);
        uint maintenanceMarginRequired = (positionSize * maintenanceMargin) /
            100;
        uint256 maximumLossUserCanBear = collateral - maintenanceMarginRequired;
        uint256 maxSustainablePriceDelta = (maximumLossUserCanBear *
            entryPrice) / positionSize;

        return
            longOrShort == Direction.Long
                ? entryPrice - maxSustainablePriceDelta
                : entryPrice + maxSustainablePriceDelta;
    }

    function createUserPosition(
        uint256 maintenanceMargin,
        PositionParams memory pos,
        uint256 userNonce
    ) internal view returns (UserPosition memory outputPosition) {
        uint256 positionSize = estimatePositionSize(
            pos.leverage,
            pos.collateralAmount
        );
        uint256 liquidationPrice = estimateLiquidationPrice(
            pos.entryPrice,
            pos.leverage,
            pos.collateralAmount,
            maintenanceMargin,
            pos.longOrShort
        );
        bytes32 positionId = id(pos.positionOwner, userNonce);

        outputPosition = UserPosition({
            liquidationPrice: liquidationPrice,
            entryPrice: pos.entryPrice,
            leverage: pos.leverage,
            collateral: pos.collateralAmount,
            positionSize: positionSize,
            positionId: positionId,
            positionOwner: pos.positionOwner,
            // priceFeedAddress: pos.priceFeedAddress,
            longOrShort: pos.longOrShort,
            lastUpdatedTime: block.timestamp
        });
    }

    function createNewMarket(
        MarketCreationParams calldata newMarket,
        mapping(address => LeverageMarket) storage allMarkets
    ) internal {
        //TODO: ensure that only 1 market can be created per address
        allMarkets[newMarket.priceFeedAddress] = LeverageMarket({
            priceFeedAddress: newMarket.priceFeedAddress,
            assetSize: newMarket.assetSize,
            totalLongSize: 0,
            totalShortSize: 0,
            decimals: newMarket.decimals,
            maximumLeverage: newMarket.maximumLeverage
        });
    }

    function updateMarketPricefeed(
        address oldPricefeed,
        address newPricefeed,
        mapping(address => LeverageMarket) storage allMarkets
    ) internal {
        LeverageMarket storage oldInfo = allMarkets[oldPricefeed];
        oldInfo.priceFeedAddress = newPricefeed;
        allMarkets[newPricefeed] = oldInfo;
        delete allMarkets[oldPricefeed];
    }

    function updateMarketLeverage(
        address pricefeedAddress,
        uint256 newLeverageValue,
        mapping(address => LeverageMarket) storage allMarkets
    ) internal {
        allMarkets[pricefeedAddress].maximumLeverage = newLeverageValue;
    }
}
