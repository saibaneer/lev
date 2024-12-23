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
    address public vaultAddress;
    address public collateralTokenAddress;
    address public oracleAddress;
    uint8 public constant MAINTENANCE_MARGIN = 5;

    function createNewMarket(
        MarketLib.MarketCreationParams calldata newMarket
    ) external {
        //require that the market does not previously exist.
        require(vaultAddress != address(0), "Set vault address");
        
        // create position manager
        address newPositionManager = factoryPositionManager.clone();
        MarketLib.createNewMarket(newMarket, markets, newPositionManager);
        IPositionManager(newPositionManager).initialize(
            newMarket.priceFeedAddress,
            address(this),
            MAINTENANCE_MARGIN,
            vaultAddress,
            collateralTokenAddress,
            oracleAddress
        );
    }

    function updateMarketPricefeed(
        address oldPricefeed,
        address newPricefeed
    ) external {
        //require that address zero is not allowed
        MarketLib.updateMarketPricefeed(oldPricefeed, newPricefeed, markets);
    }

    function updateMarketLeverage(
        address pricefeedAddress,
        uint256 newLeverageValue
    ) external {
        MarketLib.updateMarketLeverage(
            pricefeedAddress,
            newLeverageValue,
            markets
        );
    }

    function addToTotalMarketPositions(
        MarketLib.UserPosition calldata userPos,
        address _pricefeed
    ) external {
        MarketLib.addToTotalMarketPositions(userPos, markets, _pricefeed);
    }

    function reduceFromTotalMarketPositions(
        MarketLib.UserPosition calldata userPos,
        address _pricefeed
    ) external {
        MarketLib.reduceFromTotalMarketPositions(userPos, markets, _pricefeed);
    }

    function setVaultAddress(address _vaultAddress) external {
        vaultAddress = _vaultAddress;
    }

    function setCollateralTokenAddress(
        address _collateralTokenAddress
    ) external {
        collateralTokenAddress = _collateralTokenAddress;
    }

    function setFactoryPositionManager(address _address) external {
        factoryPositionManager = _address;
    }

    function setOracleAddress(address _address) external {
        oracleAddress = _address;
    }
}
