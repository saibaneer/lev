// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./TestMaxSkipListV2Lib.sol";
import "./MinSkipListV2Lib.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@openzeppelin/contracts/utils/structs/Heap.sol";
import "hardhat/console.sol";
import "./StructsLib.sol";
import "./LiquidationMathLib.sol";

library MarketLib {
    using MaxSkipListV2 for MaxSkipListV2.List;
    using MinSkipListV2 for MinSkipListV2.List;
    using StructsLib for *;
    using LiquidationMath for *;

    uint256 constant SCALE = 1e18;
    uint256 constant LEVERAGE_SCALE = 100;

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
        return (leverage * collateral)/100;
    }

    
    function createUserPosition(
        StructsLib.PositionParams memory pos,
        uint256 userNonce,
        address pricefeedAddress,
        uint256 entryPrice
    ) internal view returns (StructsLib.UserPosition memory outputPosition) {
        uint256 positionSize = estimatePositionSize(
            pos.leverage,
            pos.collateralAmount
        );
        uint256 liquidationPrice = LiquidationMath.calculateLiquidationPrice(
            pos.longOrShort == StructsLib.Direction.Long,
            entryPrice,
            pos.leverage
        );
        bytes32 positionId = id(pos.positionOwner, userNonce, pricefeedAddress);

        outputPosition = StructsLib.UserPosition({
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
        mapping(bytes32 => StructsLib.UserPosition) storage userPositionMappings
    )
        internal
        view
        returns (uint256 newLiqPrice, uint256 newEffectiveLeverage)
    {
        StructsLib.UserPosition storage pos = userPositionMappings[positionId];

        console.log("Current collateral before casting is: ", pos.collateral);

        // Convert to signed for safe math
        int256 currentCollateral = int256(pos.collateral);
        console.log("Current collateral is: ");
        console.logInt(currentCollateral);

        int256 newCollateralSigned = currentCollateral + collateralChange;
        console.log("Collateral change is: ");
        console.logInt(collateralChange);

        console.log("New collateral is: ");
        console.logInt(newCollateralSigned);

        // Ensure new collateral is positive
        require(newCollateralSigned > 0, "Invalid collateral amount");

        uint256 newCollateral = uint256(newCollateralSigned);

        // Calculate new effective leverage in bips
        newEffectiveLeverage = pos.positionSize*100/newCollateral;
        console.log("New collateral is: %s", newCollateral);
        console.log("Position size is: %s", pos.positionSize);
        console.log("New effective leverage is: %s", newEffectiveLeverage);

        // Calculate new liquidation price using individual parameters
        newLiqPrice = LiquidationMath.calculateLiquidationPrice(
            pos.longOrShort == StructsLib.Direction.Long,
            pos.entryPrice,
            newEffectiveLeverage
        );

        return (newLiqPrice, newEffectiveLeverage);
    }

    function createNewMarket(
        StructsLib.MarketCreationParams calldata newMarket,
        mapping(address => StructsLib.LeverageMarket) storage allMarkets,
        address _positionManagerAddress
    ) internal {
        //TODO: ensure that only 1 market can be created per address
        allMarkets[newMarket.priceFeedAddress] = StructsLib.LeverageMarket({
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
        mapping(address => StructsLib.LeverageMarket) storage allMarkets
    ) internal {
        StructsLib.LeverageMarket storage oldInfo = allMarkets[oldPricefeed];
        oldInfo.priceFeedAddress = newPricefeed;
        allMarkets[newPricefeed] = oldInfo;
        delete allMarkets[oldPricefeed];
    }

    function updateMarketLeverage(
        address pricefeedAddress,
        uint256 newLeverageValue,
        mapping(address => StructsLib.LeverageMarket) storage allMarkets
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
        StructsLib.UserPosition calldata userPos,
        mapping(address => StructsLib.LeverageMarket) storage markets,
        address _pricefeed
    ) internal {
        require(
            markets[_pricefeed].priceFeedAddress == _pricefeed,
            "Bad market address"
        );
        if (userPos.longOrShort == StructsLib.Direction.Long) {
            markets[_pricefeed].totalLongSize += userPos.positionSize;
        } else {
            markets[_pricefeed].totalShortSize += userPos.positionSize;
        }
    }

    function reduceFromTotalMarketPositions(
        StructsLib.UserPosition calldata userPos,
        mapping(address => StructsLib.LeverageMarket) storage markets,
        address _pricefeed
    ) internal {
        require(
            markets[_pricefeed].priceFeedAddress == _pricefeed,
            "Bad market address"
        );
        if (userPos.longOrShort == StructsLib.Direction.Long) {
            markets[_pricefeed].totalLongSize -= userPos.positionSize;
        } else {
            markets[_pricefeed].totalShortSize -= userPos.positionSize;
        }
    }

    function cleanupSkipLists(
        StructsLib.UserPosition storage pos,
        mapping(uint256 => bytes32[]) storage liquidationMappings,
        MaxSkipListV2.List storage priceListLongs,
        MinSkipListV2.List storage priceListShorts
    ) internal {
        if (
            priceListLongs.exists(pos.liquidationPrice) &&
            liquidationMappings[pos.liquidationPrice].length < 2
        ) { 
            // console.log("Liquidation mapping at the selected price, position zero: ", liquidationMappings[pos.liquidationPrice][0]);
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
        StructsLib.UserPosition memory createdPosition,
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
            if (createdPosition.longOrShort == StructsLib.Direction.Long) {
                priceListLongs.insert(liquidationPrice);
            } else {
                priceListShorts.insert(liquidationPrice);
            }
        }
        // console.log("About to write position ID to liquidation mapping...");
        // Add position to liquidation mappings
        liquidationMappings[liquidationPrice].push(positionId);
        // console.log("done...");
        // console.log("")
    }

    // function calculatePnL(
    //     StructsLib.UserPosition memory userPosition,
    //     uint256 currentPrice,
    //     uint256 minimumPrice,
    //     uint256 minimumPositionSize,
    //     uint256 minimumPnl
    // ) internal pure returns (int256) {
    //     // Input validation
    //     require(userPosition.entryPrice >= minimumPrice, "Entry price too low");
    //     require(currentPrice >= minimumPrice, "Current price too low");
    //     require(
    //         userPosition.positionSize >= minimumPositionSize,
    //         "Position too small"
    //     );

    //     int256 size = int256(userPosition.positionSize);
    //     int256 entryPrice = int256(userPosition.entryPrice);
    //     int256 current = int256(currentPrice);

    //     // Use OpenZeppelin's Math.max for uint256s
    //     uint256 maxPrice = Math.max(userPosition.entryPrice, currentPrice);

    //     // Check for overflow before multiplication
    //     require(
    //         size <= type(int256).max / int256(maxPrice),
    //         "Position size too large"
    //     );

    //     int256 pnl;
    //     if (userPosition.longOrShort == StructsLib.Direction.Long) {
    //         // Prevent underflow in price difference
    //         require(
    //             current >= entryPrice - type(int256).max / size,
    //             "Price difference too large"
    //         );
    //         require(
    //             current <= entryPrice + type(int256).max / size,
    //             "Price difference too large"
    //         );

    //         int256 priceDiff = current - entryPrice;
    //         pnl = (size * priceDiff) / entryPrice;
    //     } else {
    //         // Similar checks for short positions
    //         require(
    //             entryPrice >= current - type(int256).max / size,
    //             "Price difference too large"
    //         );
    //         require(
    //             entryPrice <= current + type(int256).max / size,
    //             "Price difference too large"
    //         );

    //         int256 priceDiff = entryPrice - current;
    //         pnl = (size * priceDiff) / entryPrice;
    //     }

    //     // Handle dust amounts using OpenZeppelin's SignedMath.abs
    //     if (SignedMath.abs(pnl) < minimumPnl) {
    //         return 0;
    //     }

    //     return pnl;
    // }

    function validateLiquidation(
        StructsLib.UserPosition storage pos,
        address liquidator
    ) internal view {
        require(pos.positionOwner != address(0), "Position does not exist");
        require(
            pos.positionOwner != liquidator,
            "You cannot liquidate your own position"
        );
    }

    function isLiquidatable(
        StructsLib.UserPosition storage pos,
        uint256 currentPrice
    ) internal view returns (bool) {
        if (pos.longOrShort == StructsLib.Direction.Long) {
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
        StructsLib.UserPosition storage pos,
        bytes32 positionId,
        mapping(address => bytes32[]) storage userToPositionMappings,
        mapping(uint256 => bytes32[]) storage liquidationMappings,
        mapping(bytes32 => StructsLib.UserPosition)
            storage idToPositionMappings,
        MaxSkipListV2.List storage priceListLongs,
        MinSkipListV2.List storage priceListShorts
    ) internal {
        MarketLib.removePositionFromUserPositionIdMappings(
            pos.positionId,
            pos.positionOwner,
            userToPositionMappings
        );

        MarketLib.cleanupSkipLists(
            pos,
            liquidationMappings,
            priceListLongs,
            priceListShorts
        );

        MarketLib.removePositionFromLiquidationMappings(
            positionId,
            pos.liquidationPrice,
            liquidationMappings
        );

        

        delete idToPositionMappings[positionId];
    }
}
