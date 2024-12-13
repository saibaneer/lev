// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;


import "./IMarketRegistry.sol";
import "./structs/MarketLib.sol";

contract MarketRegistry is IMarketRegistry {

    using MarketLib for *;


    mapping(address => MarketLib.LeverageMarket) public markets;


    function createNewMarket(
        MarketLib.MarketCreationParams calldata newMarket
    ) external{
        //require that the market does not previously exist.
        MarketLib.createNewMarket(newMarket, markets);
        // create position manager
    }
    function updateMarketPricefeed(
        address oldPricefeed,
        address newPricefeed
    ) external{
        //require that address zero is not allowed
        MarketLib.updateMarketPricefeed(oldPricefeed, newPricefeed, markets);
    }
    function updateMarketLeverage(
        address pricefeedAddress,
        uint256 newLeverageValue
    ) external{
        MarketLib.updateMarketLeverage(pricefeedAddress, newLeverageValue, markets);
    }

    function updateTotalLongs() external{}
    function updateTotalShorts() external{}
}