// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/structs/Heap.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./IPositionManager.sol";
import "./IMarketRegistry.sol";
import "./structs/MarketLib.sol";
import "./structs/MaxSkipListV2Lib.sol";
import "./structs/MinSkipListV2Lib.sol";

contract PositionManager is Initializable, IPositionManager {
    using MarketLib for *;

    using MaxSkipListV2 for MaxSkipListV2.List;
    using MinSkipListV2 for MinSkipListV2.List;

    MaxSkipListV2.List private priceListLongs;
    MinSkipListV2.List private priceListShorts;

    address public pricefeedAddress;
    address public marketRegistry;
    mapping(uint256 => bytes32[]) public liquidationMappings;
    mapping(bytes32 => MarketLib.UserPosition) public userPositionMappings;
    mapping(address => uint256) public userNonce;
    uint8 public maintenanceMargin;

    function initialize(
        address _pricefeed,
        address _marketRegistry,
        uint8 _maintenanceMargin
    ) public initializer {
        priceListLongs.initialize();
        priceListShorts.initialize();
        pricefeedAddress = _pricefeed;
        maintenanceMargin = _maintenanceMargin;
        marketRegistry = _marketRegistry;
    }

    function createPosition(
        MarketLib.PositionParams memory newPosition
    ) external {
        require(msg.sender == newPosition.positionOwner, "Sender != Owner");
        // rmbr to add the deposit to vault call.
        userNonce[newPosition.positionOwner] += 1;
        MarketLib.UserPosition memory createdPosition = MarketLib
            .createUserPosition(
                maintenanceMargin,
                newPosition,
                userNonce[newPosition.positionOwner],
                pricefeedAddress
            );

        MarketLib.pushPosition(createdPosition, liquidationMappings, priceListLongs, priceListShorts);
        // update the global long or shorts
        IMarketRegistry(marketRegistry).addToTotalMarketPositions(
                createdPosition,
                pricefeedAddress
            );
        // emit an event to indicate that a new position has been added
    }

    function updatePosition(bytes32 positionId, int256 amountToAdd) external {
    // dont forget to transfer the tokens
    // dont foget to update the AUM
    MarketLib.UserPosition storage pos = userPositionMappings[positionId];
    require(pos.positionOwner != address(0), "Position does not exist");
    //who is making the modification?
    require(pos.positionOwner == msg.sender, "Unauthorized access!");

    //only cleanup if the liquidation price previously exists, and the positionId is the only one with that liquidation price
    MarketLib.cleanupSkipLists(pos, liquidationMappings, priceListLongs, priceListShorts);

    MarketLib.removePositionFromLiquidationMappings(positionId, pos.liquidationPrice, liquidationMappings);
    uint256 newLiquidationPrice = MarketLib.getNewLiquidationPriceAfterCollateralChange(positionId, amountToAdd, maintenanceMargin, userPositionMappings);
    
    //update the info in userPositions
    pos.liquidationPrice = newLiquidationPrice;
    
    // Handle collateral update safely
    if (amountToAdd >= 0) {
        pos.collateral += uint256(amountToAdd);
    } else {
        require(pos.collateral >= uint256(-amountToAdd), "Insufficient collateral");
        pos.collateral -= uint256(-amountToAdd);
    }

    //add new liquidation price & id to mappings
    MarketLib.pushPosition(pos, liquidationMappings, priceListLongs, priceListShorts);

    //emit event to indicate added position
}

    

    function closePosition() external {}

    function liqudatePosition() external {}

    function getTopLongsByBytes32() external view returns (bytes32[] memory) {}

    function getTopLongsByObject()
        external
        view
        returns (MarketLib.UserPosition[] memory)
    {}

    function getTopShortsByBytes32() external view returns (bytes32[] memory) {}

    function getTopShortssByObject()
        external
        view
        returns (MarketLib.UserPosition[] memory)
    {}

    function updateTotalLongsOnMarket() external {}

    function updateTotalShortsOnMarket() external {}


}
