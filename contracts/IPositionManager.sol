// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "./structs/MarketLib.sol";

interface IPositionManager {
    function initialize(address _pricefeed, address _marketRegistry, uint8 _maintenanceMargin) external;
    function createPosition(MarketLib.PositionParams memory newPosition) external;
    function updatePosition(bytes32 positionId, int256 amountToAdd) external;
    function closePosition() external;

    function liqudatePosition() external;

    function getTopLongsByBytes32() external view returns(bytes32[] memory);
    function getTopLongsByObject() external view returns(MarketLib.UserPosition[] memory);

    function getTopShortsByBytes32() external view returns(bytes32[] memory);
    function getTopShortssByObject() external view returns(MarketLib.UserPosition[] memory);

    function updateTotalLongsOnMarket() external;
    function updateTotalShortsOnMarket() external;
}