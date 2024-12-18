// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;


import "./IMarketRegistry.sol";
import "./structs/MarketLib.sol";
import "./IPositionManager.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract MarketRegistry is IMarketRegistry {
    using Clones for address;
    using MarketLib for *;


    mapping(address => MarketLib.LeverageMarket) public markets;
    address public factoryPositionManager;
    uint8 public constant MAINTENANCE_MARGIN = 5;


    function createNewMarket(
        MarketLib.MarketCreationParams calldata newMarket
    ) external{
        //require that the market does not previously exist.
        MarketLib.createNewMarket(newMarket, markets);
        // create position manager
        address newPositionManager = factoryPositionManager.clone();
        IPositionManager(newPositionManager).initialize(newMarket.priceFeedAddress, address(this), MAINTENANCE_MARGIN);

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

    function addToTotalMarketPositions(MarketLib.UserPosition calldata userPos, address _pricefeed) external{
        MarketLib.addToTotalMarketPositions(userPos, markets, _pricefeed);
    }
    function reduceFromTotalMarketPositions(MarketLib.UserPosition calldata userPos, address _pricefeed) external{
        MarketLib.reduceFromTotalMarketPositions(userPos, markets, _pricefeed);
    }
}