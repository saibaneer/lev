// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./MaxSkipListV2Lib.sol";
import "./MinSkipListV2Lib.sol";

library MarketLib {
    using MaxSkipListV2 for MaxSkipListV2.List;
    using MinSkipListV2 for MinSkipListV2.List;

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

    struct PositionParams {
        uint256 entryPrice;
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

    function id(
        address positionOwner,
        uint256 userNonce,
        address pricefeedAddress
    ) internal pure returns (bytes32) {
        bytes32 positionId = keccak256(
            abi.encodePacked(positionOwner, userNonce, pricefeedAddress) //too simple will add more variables before audit
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
        uint256 userNonce,
        address pricefeedAddress
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
        bytes32 positionId = id(pos.positionOwner, userNonce, pricefeedAddress);

        outputPosition = UserPosition({
            pricefeedAddress: pricefeedAddress,
            liquidationPrice: liquidationPrice,
            entryPrice: pos.entryPrice,
            leverage: pos.leverage,
            collateral: pos.collateralAmount,
            positionSize: positionSize,
            positionId: positionId,
            positionOwner: pos.positionOwner,
            longOrShort: pos.longOrShort,
            lastUpdatedTime: block.timestamp,
            cumulativeFundingValue: 0,
            profitOrLoss: 0
        });
    }

    function removePositionFromLiquidationMappings(
        bytes32 positionId,
        uint256 liquidationPrice,
        mapping(uint256 => bytes32[]) storage liquidationMappings
    ) internal {
        require(
            liquidationMappings[liquidationPrice].length > 0,
            "No positions for this price"
        );
        if (liquidationMappings[liquidationPrice].length == 1) {
            if (liquidationMappings[liquidationPrice][0] == positionId) {
                liquidationMappings[liquidationPrice].pop();
            }
        } else {
            bytes32[] storage inStorageIds = liquidationMappings[
                liquidationPrice
            ];
            uint256 lastIndex = inStorageIds.length - 1;
            for (uint256 i; i < inStorageIds.length; i++) {
                if (inStorageIds[i] == positionId) {
                    // Swap the element to be removed with the last element
                    if (i != lastIndex) {
                        inStorageIds[i] = inStorageIds[lastIndex];
                    }
                    // Remove the last element
                    inStorageIds.pop();
                    break;
                }
            }
        }
    }

    function getNewLiquidationPriceAfterCollateralChange(
    bytes32 positionId,
    int256 collateralChange,
    uint256 maintainanceMargin,
    mapping(bytes32 => UserPosition) storage userPositionMappings
) internal view returns (uint256) {
    UserPosition storage pos = userPositionMappings[positionId];
    
    // Convert to signed for safe math
    int256 currentCollateral = int256(pos.collateral);
    int256 newCollateralSigned = currentCollateral + collateralChange;
    
    // Ensure new collateral is positive
    require(newCollateralSigned > 0, "Invalid collateral amount");
    
    uint256 newCollateral = uint256(newCollateralSigned);
    
    return estimateLiquidationPrice(
        pos.entryPrice,
        pos.leverage,
        newCollateral,
        maintainanceMargin,
        pos.longOrShort
    );
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

    function checkIfLiquidationPriceExists(
        uint256 liquidationPrice,
        mapping(uint256 => bytes32[]) storage liquidationMappings
    ) internal view returns (bool) {
        return liquidationMappings[liquidationPrice].length == 0 ? false : true;
    }

    function addToTotalMarketPositions(
        UserPosition calldata userPos,
        mapping(address => LeverageMarket) storage markets,
        address _pricefeed
    ) internal {
        require(
            markets[_pricefeed].priceFeedAddress == _pricefeed,
            "Bad market address"
        );
        if (userPos.longOrShort == Direction.Long) {
            markets[_pricefeed].totalLongSize += userPos.positionSize;
        } else {
            markets[_pricefeed].totalShortSize += userPos.positionSize;
        }
    }

    function reduceFromTotalMarketPositions(
        UserPosition calldata userPos,
        mapping(address => LeverageMarket) storage markets,
        address _pricefeed
    ) internal {
        require(
            markets[_pricefeed].priceFeedAddress == _pricefeed,
            "Bad market address"
        );
        if (userPos.longOrShort == Direction.Long) {
            markets[_pricefeed].totalLongSize -= userPos.positionSize;
        } else {
            markets[_pricefeed].totalShortSize -= userPos.positionSize;
        }
    }

    function cleanupSkipLists(
        UserPosition storage pos,
        mapping(uint256 => bytes32[]) storage liquidationMappings,
        MaxSkipListV2.List storage priceListLongs,
        MinSkipListV2.List storage priceListShorts
    ) internal {
        if (
            priceListLongs.exists(pos.liquidationPrice) &&
            liquidationMappings[pos.liquidationPrice].length < 2
        ) {
            //check the length
            require(
                liquidationMappings[pos.liquidationPrice][0] == pos.positionId,
                "Cannot modify this long position in list"
            );
            priceListLongs.remove(pos.liquidationPrice);
        } else if (
            priceListShorts.exists(pos.liquidationPrice) &&
            liquidationMappings[pos.liquidationPrice].length < 2
        ) {
            require(
                liquidationMappings[pos.liquidationPrice][0] == pos.positionId,
                "Cannot modify this short position in list"
            );
            priceListShorts.remove(pos.liquidationPrice);
        }
    }

    function pushPosition(
        MarketLib.UserPosition memory createdPosition,
        mapping(uint256 => bytes32[]) storage liquidationMappings,
        MaxSkipListV2.List storage priceListLongs,
        MinSkipListV2.List storage priceListShorts
    ) internal {
        uint256 liquidationPrice = createdPosition.liquidationPrice;
        bytes32 positionId = createdPosition.positionId;

        // Insert into skiplist if this is first position at this liquidation price
        if (
            !checkIfLiquidationPriceExists(
                liquidationPrice,
                liquidationMappings
            )
        ) {
            if (createdPosition.longOrShort == MarketLib.Direction.Long) {
                priceListLongs.insert(liquidationPrice);
            } else {
                priceListShorts.insert(liquidationPrice);
            }
        }

        // Add position to liquidation mappings
        liquidationMappings[liquidationPrice].push(positionId);
    }
}
