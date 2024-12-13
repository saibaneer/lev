// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/structs/Heap.sol";
import "./structs/MarketLib.sol";
import "./structs/MaxSkipListV2Lib.sol";
import "./structs/MinSkipListV2Lib.sol";

contract PositionManager {
    using MarketLib for *;

    using MaxSkipListV2 for MaxSkipListV2.List;
    using MinSkipListV2 for MinSkipListV2.List;

    MaxSkipListV2.List private priceListLongs;
    MinSkipListV2.List private priceListShorts;

    address public pricefeedAddress;
    mapping(uint256 => bytes32[]) public liquidationMappings;
    mapping(bytes32 => MarketLib.UserPosition) public userPositionMappings;
    constructor(address _pricefeed) {
        // Add address zero checks
        priceListLongs.initialize();
        priceListShorts.initialize();

    }

    function createPosition() external {
        //TODO : user passes in position variables and creates position
        //TODO : we check if the liquidation price already exists.
        // if it does not exist, we had it to the skiplist, and also store it on the liquidation mappings, and push position
        // if it does exist, we simply push position into the liquidation mappings
        // update the global long or shorts 
        // emit an event to indicate that a new position has been added
    }

    function modifyPosition() external {}

    function closePosition() external {}

    function liqudatePosition() external {}

    function getTopLongsByBytes32() external view returns(bytes32[] memory){}
    function getTopLongsByObject() external view returns(MarketLib.UserPosition[] memory){}

    function getTopShortsByBytes32() external view returns(bytes32[] memory){}
    function getTopShortssByObject() external view returns(MarketLib.UserPosition[] memory){}

    function updateTotalLongsOnMarket() external{}
    function updateTotalShortsOnMarket() external{}
}
