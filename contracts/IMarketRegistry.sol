// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "./library/StructsLib.sol";

interface IMarketRegistry {
    // function createNewMarket(
    //     MarketLib.MarketCreationParams calldata newMarket
    // ) external;

    function updateMarketPricefeed(
        address oldPricefeed,
        address newPricefeed
    ) external;

    function updateMarketLeverage(
        address pricefeedAddress,
        uint256 newLeverageValue
    ) external;

    function addToTotalMarketPositions(StructsLib.UserPosition calldata userPos, address _pricefeed) external;

    function reduceFromTotalMarketPositions(StructsLib.UserPosition calldata userPos, address _pricefeed) external;
}
