// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IPositionManager.sol";
import "./IVault.sol";
import "./IMarketRegistry.sol";
import "./library/MarketLib.sol";
import "./library/TestMaxSkipListV2Lib.sol";
import "./library/MinSkipListV2Lib.sol";
import "./library/ConstantsLib.sol";
import "./library/ErrorLib.sol";
import "./library/LiquidationMathLib.sol";
import "./IOracle.sol";

/// @title Position Manager Contract
/// @notice Manages leveraged trading positions including creation, updates, and liquidations
/// @dev Implements upgradeable pattern and uses skip lists for efficient position tracking
contract PositionManager is Initializable, IPositionManager {
    using ConstantsLib for *;
    using MarketLib for *;
    using MaxSkipListV2 for MaxSkipListV2.List;
    using MinSkipListV2 for MinSkipListV2.List;
    using SafeERC20 for IERC20;
    using LiquidationMath for *;

    /// @notice Skip list tracking long positions by price
    MaxSkipListV2.List private priceListLongs;

    /// @notice Skip list tracking short positions by price
    MinSkipListV2.List private priceListShorts;

    /// @notice Address of the oracle contract
    address public oracleAddress;

    /// @notice Address of the price feed contract
    address public pricefeedAddress;

    /// @notice Address of the market registry contract
    address public marketRegistry;

    /// @notice Address of the vault contract that holds collateral
    address public vaultAddress;

    /// @notice Address of the token used as collateral
    address public collateralTokenAddress;

    /// @notice Maps liquidation prices to arrays of position IDs
    mapping(uint256 => bytes32[]) public liquidationMappings;

    /// @notice Maps position IDs to position details
    mapping(bytes32 => StructsLib.UserPosition) public idToPositionMappings;

    /// @notice Tracks the nonce for each user's positions
    mapping(address => uint256) public userNonce;

    /// @notice Maps user addresses to their position IDs
    mapping(address => bytes32[]) public userToPositionMappings;


    /// @notice Initializes the contract with required parameters
    /// @param _pricefeed Address of the price feed contract
    /// @param _marketRegistry Address of the market registry contract
    /// @param _maintenanceMargin Maintenance margin percentage
    /// @param _vaultAddress Address of the vault contract
    /// @param _collateralTokenAddress Address of the collateral token
    function initialize(
        address _pricefeed,
        address _marketRegistry,
        uint256 _maintenanceMargin,
        address _vaultAddress,
        address _collateralTokenAddress,
        address _oracleAddress
    ) public initializer {
        priceListLongs.initialize();
        priceListShorts.initialize();
        pricefeedAddress = _pricefeed;
        marketRegistry = _marketRegistry;
        vaultAddress = _vaultAddress;
        collateralTokenAddress = _collateralTokenAddress;
        oracleAddress = _oracleAddress;
    }

    /// @notice Creates a new trading position
    /// @dev Updates relevant mappings and market registry
    /// @param newPosition Parameters for the new position
    function createMarketPosition(
        StructsLib.PositionParams memory newPosition
    ) external {
        require(
            msg.sender == newPosition.positionOwner,
            ErrorLib.UNAUTHORIZED_ACCESS
        );
        require(
            newPosition.collateralAmount <= ConstantsLib.MAXIMUM_COLLATERAL,
            ErrorLib.MAX_COLLATERAL_EXCEEDED
        );
        userNonce[newPosition.positionOwner] += 1;
        uint256 currentAssetPrice = IOracle(oracleAddress).getAssetPrice(
            pricefeedAddress
        );
        StructsLib.UserPosition memory createdPosition = MarketLib
            .createUserPosition(
                newPosition,
                userNonce[newPosition.positionOwner],
                pricefeedAddress,
                currentAssetPrice
            );

        MarketLib.pushPosition(
            createdPosition,
            liquidationMappings,
            priceListLongs,
            priceListShorts
        );
        // liquidationMappings[createdPosition.liquidationPrice].push(createdPosition.positionId);
        userToPositionMappings[msg.sender].push(createdPosition.positionId);
        // Store the position data in idToPositionMappings
        idToPositionMappings[createdPosition.positionId] = createdPosition;

        IMarketRegistry(marketRegistry).addToTotalMarketPositions(
            createdPosition,
            pricefeedAddress
        );
        IERC20 collateralToken = IERC20(collateralTokenAddress);
        collateralToken.safeTransferFrom(
            msg.sender,
            address(this),
            createdPosition.collateral
        );
        collateralToken.safeTransferFrom(msg.sender, vaultAddress, 0); //add fee
    }

    /// @notice Updates an existing position's collateral
    /// @dev Recalculates liquidation price and updates relevant mappings
    /// @param positionId The ID of the position to update
    /// @param amountToAdd The amount of collateral to add (positive) or remove (negative)
    function updatePosition(bytes32 positionId, int256 amountToAdd) external {
        StructsLib.UserPosition storage pos = idToPositionMappings[positionId];
        require(
            pos.positionOwner != address(0),
            ErrorLib.POSITION_DOES_NOT_EXIST
        );
        require(pos.positionOwner == msg.sender, ErrorLib.UNAUTHORIZED_ACCESS);

        // Clean up old position data
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

        

        // Then calculate new liquidation price based on updated collateral
        (uint256 newLiquidationPrice, uint256 effectiveLeverage) = MarketLib
            .getNewLiquidationPriceAfterCollateralChange(
                positionId,
                amountToAdd,
                idToPositionMappings
            );

        // Update collateral first
        if (amountToAdd >= 0) {
            pos.collateral += uint256(amountToAdd);
        } else {
            require(
                pos.collateral >= uint256(-amountToAdd),
                ErrorLib.INSUFFICIENT_COLLATERAL
            );
            pos.collateral -= uint256(-amountToAdd);
        }

        // Verify new liquidation price against current asset price
        uint256 assetPrice = IOracle(oracleAddress).getAssetPrice(
            pricefeedAddress
        );
        if (pos.longOrShort == StructsLib.Direction.Long) {
            require(
                newLiquidationPrice < assetPrice,
                ErrorLib.PRICE_IS_HIGHER_THAN_CURRENT_ASSET_PRICE
            );
        } else {
            require(
                newLiquidationPrice > assetPrice,
                ErrorLib.PRICE_IS_LOWER_THAN_CURRENT_ASSET_PRICE
            );
        }

        // Update position with new values
        pos.liquidationPrice = newLiquidationPrice;
        pos.leverage = effectiveLeverage;

        // Add updated position back to data structures
        MarketLib.pushPosition(
            pos,
            liquidationMappings,
            priceListLongs,
            priceListShorts
        );

        // Handle token transfers
        IERC20 collateralToken = IERC20(collateralTokenAddress);
        if (amountToAdd > 0) {
            collateralToken.safeTransferFrom(
                msg.sender,
                address(this),
                uint256(amountToAdd)
            );
            collateralToken.safeTransferFrom(msg.sender, vaultAddress, 0); //add fee
        } else {
            collateralToken.safeTransfer(msg.sender, uint256(-amountToAdd));
        }
    }

    /// @notice Liquidates a position that has reached its liquidation price
    /// @dev Calculates fees, cleans up position data, and distributes tokens
    /// @param positionId The ID of the position to liquidate
    function liquidatePosition(bytes32 positionId) external {
        StructsLib.UserPosition storage pos = idToPositionMappings[positionId];
        MarketLib.validateLiquidation(pos, msg.sender);

        uint256 currentAssetPrice = IOracle(oracleAddress).getAssetPrice(
            pos.pricefeedAddress
        );
        require(
            MarketLib.isLiquidatable(pos, currentAssetPrice),
            ErrorLib.CANNOT_BE_LIQUIDATED
        );

        (uint256 liquidationFee, uint256 vaultFunds) = MarketLib.calculateFees(
            pos.collateral
        );

        MarketLib.cleanupPosition(
            pos,
            positionId,
            userToPositionMappings,
            liquidationMappings,
            idToPositionMappings,
            priceListLongs,
            priceListShorts
        );

        distributeTokens(liquidationFee, vaultFunds);
    }

    /// @notice Distributes liquidation fees and remaining funds
    /// @dev Transfers tokens to liquidator and vault
    /// @param liquidationFee Amount to be paid to the liquidator
    /// @param vaultFunds Amount to be returned to the vault
    function distributeTokens(
        uint256 liquidationFee,
        uint256 vaultFunds
    ) private {
        IERC20 collateralToken = IERC20(collateralTokenAddress);
        collateralToken.safeTransfer(msg.sender, liquidationFee);
        collateralToken.safeTransfer(vaultAddress, vaultFunds);
    }

    function closePosition(bytes32 positionId) external {
        StructsLib.UserPosition memory pos = idToPositionMappings[positionId];
        require(
            pos.positionOwner != address(0),
            ErrorLib.POSITION_DOES_NOT_EXIST
        );
        require(pos.positionOwner == msg.sender, ErrorLib.UNAUTHORIZED_ACCESS);
        uint256 currentAssetPrice = IOracle(oracleAddress).getAssetPrice(
            pos.pricefeedAddress
        );
        //calculate PnL
        int256 pnl = LiquidationMath.calculatePnL(
            pos,
            currentAssetPrice,
            ConstantsLib.MIN_PRICE,
            ConstantsLib.MIN_POSITION_SIZE,
            ConstantsLib.MIN_P_N_L
        );
        // if in loss deduct
        uint256 amountDue;
        
        if (pnl < 0) {
            amountDue = pos.collateral - uint256(pnl);
        } else {
            amountDue = pos.collateral + uint256(pnl);
        }
        console.log("Amount due to user is: ", amountDue);
        StructsLib.UserPosition storage s_pos = idToPositionMappings[positionId];
        MarketLib.cleanupPosition(
            s_pos,
            positionId,
            userToPositionMappings,
            liquidationMappings,
            idToPositionMappings,
            priceListLongs,
            priceListShorts
        );
        IVault(vaultAddress).payUser(msg.sender, amountDue);

        //emit events
        //if in profit payout to the caller (provided they are the owner)
    }

    function getAllPositionsFromUser(
        address _user
    ) external view returns (bytes32[] memory) {
        return userToPositionMappings[_user];
    }

    function getLiquidationMappingsFromPrice(
        uint256 price
    ) external view returns (bytes32[] memory) {
        return liquidationMappings[price];
    }

    function getTopLongsByBytes32() external view returns (bytes32[] memory) {
        uint256 highestLong = priceListLongs.getHighestPrice();
        return liquidationMappings[highestLong];
        // return priceListLongs.
    }

    function getTopLongsByObject()
        external
        view
        returns (StructsLib.UserPosition[] memory)
    {
        uint256 highestLong = priceListLongs.getHighestPrice();
        require(highestLong > 0, "No long positions exist");

        bytes32[] memory positionsAtPrice = liquidationMappings[highestLong];
        uint256 positionCount = positionsAtPrice.length;
        require(positionCount > 0, "No positions at highest price");

        // Create return array
        StructsLib.UserPosition[]
            memory allPositions = new StructsLib.UserPosition[](positionCount);

        // Fill array with positions
        for (uint256 i; i < liquidationMappings[highestLong].length; i++) {
            allPositions[i] = idToPositionMappings[positionsAtPrice[i]];
        }
        return allPositions;
    }

    function getTopShortsByBytes32() external view returns (bytes32[] memory) {
        uint256 shortestLong = priceListShorts.getLowestPrice();
        return liquidationMappings[shortestLong];
    }

    function getTopShortssByObject()
        external
        view
        returns (StructsLib.UserPosition[] memory)
    {
        uint256 shortestLong = priceListShorts.getLowestPrice();
        require(shortestLong > 0, "No long positions exist");

        bytes32[] memory positionsAtPrice = liquidationMappings[shortestLong];
        uint256 positionCount = positionsAtPrice.length;
        require(positionCount > 0, "No positions at highest price");

        // Create return array
        StructsLib.UserPosition[]
            memory allPositions = new StructsLib.UserPosition[](positionCount);

        // Fill array with positions
        for (uint256 i; i < liquidationMappings[shortestLong].length; i++) {
            allPositions[i] = idToPositionMappings[
                positionsAtPrice[shortestLong][i]
            ];
        }
        return allPositions;
    }
}
