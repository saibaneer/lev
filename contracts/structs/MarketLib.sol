// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./MaxSkipListV2Lib.sol";
import "./MinSkipListV2Lib.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";

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
        address pricefeedAddress,
        uint256 entryPrice
    ) internal view returns (UserPosition memory outputPosition) {
        uint256 positionSize = estimatePositionSize(
            pos.leverage,
            pos.collateralAmount
        );
        uint256 liquidationPrice = estimateLiquidationPrice(
            entryPrice,
            pos.leverage,
            pos.collateralAmount,
            maintenanceMargin,
            pos.longOrShort
        );
        bytes32 positionId = id(pos.positionOwner, userNonce, pricefeedAddress);

        outputPosition = UserPosition({
            pricefeedAddress: pricefeedAddress,
            liquidationPrice: liquidationPrice,
            entryPrice: entryPrice,
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

    function removePositionFromUserPositionIdMappings(
        bytes32 positionId,
        address positionOwner,
        mapping(address => bytes32[]) storage userToPositionMappings
    ) internal {
        require(
            userToPositionMappings[positionOwner].length > 0,
            "No positions for this user"
        );
        if (userToPositionMappings[positionOwner].length == 1) {
            if (userToPositionMappings[positionOwner][0] == positionId) {
                userToPositionMappings[positionOwner].pop();
            }
        } else {
            bytes32[] storage inStorageIds = userToPositionMappings[
                positionOwner
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

        return
            estimateLiquidationPrice(
                pos.entryPrice,
                pos.leverage,
                newCollateral,
                maintainanceMargin,
                pos.longOrShort
            );
    }

    function createNewMarket(
        MarketCreationParams calldata newMarket,
        mapping(address => LeverageMarket) storage allMarkets,
        address _positionManagerAddress
    ) internal {
        //TODO: ensure that only 1 market can be created per address
        allMarkets[newMarket.priceFeedAddress] = LeverageMarket({
            priceFeedAddress: newMarket.priceFeedAddress,
            positionManagerAddress: _positionManagerAddress,
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
        UserPosition memory createdPosition,
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

    function calculatePnL(
        UserPosition memory userPosition,
        uint256 currentPrice,
        uint256 minimumPrice,
        uint256 minimumPositionSize,
        uint256 minimumPnl
    ) internal view returns (int256) {
        // Input validation
        require(userPosition.entryPrice >= minimumPrice, "Entry price too low");
        require(currentPrice >= minimumPrice, "Current price too low");
        require(
            userPosition.positionSize >= minimumPositionSize,
            "Position too small"
        );

        int256 size = int256(userPosition.positionSize);
        int256 entryPrice = int256(userPosition.entryPrice);
        int256 current = int256(currentPrice);

        // Use OpenZeppelin's Math.max for uint256s
        uint256 maxPrice = Math.max(userPosition.entryPrice, currentPrice);

        // Check for overflow before multiplication
        require(
            size <= type(int256).max / int256(maxPrice),
            "Position size too large"
        );

        int256 pnl;
        if (userPosition.longOrShort == Direction.Long) {
            // Prevent underflow in price difference
            require(
                current >= entryPrice - type(int256).max / size,
                "Price difference too large"
            );
            require(
                current <= entryPrice + type(int256).max / size,
                "Price difference too large"
            );

            int256 priceDiff = current - entryPrice;
            pnl = (size * priceDiff) / entryPrice;
        } else {
            // Similar checks for short positions
            require(
                entryPrice >= current - type(int256).max / size,
                "Price difference too large"
            );
            require(
                entryPrice <= current + type(int256).max / size,
                "Price difference too large"
            );

            int256 priceDiff = entryPrice - current;
            pnl = (size * priceDiff) / entryPrice;
        }

        // Handle dust amounts using OpenZeppelin's SignedMath.abs
        if (SignedMath.abs(pnl) < minimumPnl) {
            return 0;
        }

        return pnl;
    }

    function validateLiquidation(
        UserPosition storage pos,
        address liquidator
    ) internal view {
        require(pos.positionOwner != address(0), "Position does not exist");
        require(
            pos.positionOwner != liquidator,
            "You cannot liquidate your own position"
        );
    }

    function isLiquidatable(
        UserPosition storage pos,
        uint256 currentPrice
    ) internal view returns (bool) {
        if (pos.longOrShort == MarketLib.Direction.Long) {
            return currentPrice <= pos.liquidationPrice;
        } else {
            return currentPrice >= pos.liquidationPrice;
        }
    }

    function calculateFees(
        uint256 collateral
    ) internal pure returns (uint256 liquidationFee, uint256 vaultFunds) {
        liquidationFee = (5 * collateral) / 100;
        vaultFunds = collateral - liquidationFee;
        return (liquidationFee, vaultFunds);
    }

    function cleanupPosition(
        MarketLib.UserPosition storage pos,
        bytes32 positionId,
        mapping(address => bytes32[]) storage userToPositionMappings,
        mapping(uint256 => bytes32[]) storage liquidationMappings,
        mapping(bytes32 => UserPosition) storage idToPositionMappings,
        MaxSkipListV2.List storage priceListLongs,
        MinSkipListV2.List storage priceListShorts
    ) internal {
        MarketLib.removePositionFromUserPositionIdMappings(
            pos.positionId,
            pos.positionOwner,
            userToPositionMappings
        );

        MarketLib.removePositionFromLiquidationMappings(
            positionId,
            pos.liquidationPrice,
            liquidationMappings
        );

        MarketLib.cleanupSkipLists(
            pos,
            liquidationMappings,
            priceListLongs,
            priceListShorts
        );

        delete idToPositionMappings[positionId];
    }
}
