// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "./structs/MarketLib.sol";

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

    function addToTotalMarketPositions(MarketLib.UserPosition calldata userPos, address _pricefeed) external;

    function reduceFromTotalMarketPositions(MarketLib.UserPosition calldata userPos, address _pricefeed) external;
}
