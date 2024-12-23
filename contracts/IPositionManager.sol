// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "./structs/MarketLib.sol";

interface IPositionManager {
    function initialize(
        address _pricefeed,
        address _marketRegistry,
        uint8 _maintenanceMargin,
        address _vaultAddress,
        address _collateralTokenAddress,
        address _oracleAddress
    ) external;

    function createMarketPosition(
        MarketLib.PositionParams memory newPosition
    ) external;

    function updatePosition(bytes32 positionId, int256 amountToAdd) external;

    function closePosition(bytes32 positionId) external;

    function liquidatePosition(bytes32 positionId) external;

    function getTopLongsByBytes32() external view returns (bytes32[] memory);

    function getTopLongsByObject()
        external
        view
        returns (MarketLib.UserPosition[] memory);

    function getTopShortsByBytes32() external view returns (bytes32[] memory);

    function getTopShortssByObject()
        external
        view
        returns (MarketLib.UserPosition[] memory);
}
