// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./StructsLib.sol";
import "hardhat/console.sol";

/**
 * @title LiquidationMath
 * @dev Library for calculating liquidation prices with dynamic leverage and maintenance margins
 */
library LiquidationMath {
    
    // Global constants
    uint256 constant SCALING_FACTOR = 1e18;
    uint256 constant BASE_RATE = 20e16;      // 20%
    uint256 constant MIN_MMR = 15e15;        // 1.5%
    uint256 constant PREMIUM_COEFFICIENT = 0.02e18; // 2% premium coefficient
    uint256 constant BASIS_POINTS = 100;

    /**
     * @dev Calculate the maintenance margin rate based on leverage
     */
    function calculateMaintenanceMarginRate(uint256 leverageBips) internal pure returns (uint256) {
        require(leverageBips > 0, "Leverage must be greater than zero");

        console.log("Starting Maintenance Margin Rate Calculation...");
        console.log("Leverage (Bips): %s", leverageBips);

        uint256 actualLeverage = leverageBips / BASIS_POINTS;

        // Calculate square root of (2/leverage)
        uint256 numerator = 2 * SCALING_FACTOR;
        uint256 denominator = actualLeverage;
        uint256 ratio = (numerator * SCALING_FACTOR) / denominator;

        uint256 sqrtRatio = Math.sqrt(ratio);

        uint256 maintenanceMarginRate = ((BASE_RATE * sqrtRatio) / SCALING_FACTOR) + MIN_MMR;

        console.log("Actual Leverage: %s", actualLeverage);
        console.log("Square Root Component: %s", sqrtRatio);
        console.log("Calculated MMR: %s", maintenanceMarginRate);

        return maintenanceMarginRate;
    }

    /**
     * @dev Calculate the liquidation price for a position
     */
    function calculateLiquidationPrice(
        bool isLong,
        uint256 entryPrice,
        uint256 leverageBips
    ) internal pure returns (uint256) {
        require(entryPrice > 0, "Entry price must be greater than zero");
        require(leverageBips > BASIS_POINTS, "Leverage must be greater than 1x (100 basis points)");

        console.log("Entry Price: %s", entryPrice);
        console.log("Leverage Bips: %s", leverageBips);

        // Convert leverage from basis points to fixed-point
        uint256 leverage = (leverageBips * SCALING_FACTOR) / BASIS_POINTS;
        console.log("Leverage (Fixed Point): %s", leverage);

        // Compute leverage^2
        uint256 leverageSquared = (leverage * leverage) / SCALING_FACTOR;
        console.log("Leverage Squared: %s", leverageSquared);

        // Compute 1 / leverage and 1 / leverage^2
        uint256 oneOverLeverage = (SCALING_FACTOR * SCALING_FACTOR) / leverage;
        uint256 oneOverLeverageSquared = (SCALING_FACTOR * SCALING_FACTOR) / leverageSquared;
        console.log("One Over Leverage: %s", oneOverLeverage);
        console.log("One Over Leverage Squared: %s", oneOverLeverageSquared);

        // Default liquidation adjustment based on leverage
        uint256 liquidationAdjustment = SCALING_FACTOR - oneOverLeverage;
        console.log("Liquidation Adjustment: %s", liquidationAdjustment);

        // Premium adjustment based on leverage^2
        uint256 premiumAdjustment = (PREMIUM_COEFFICIENT * (SCALING_FACTOR - oneOverLeverageSquared)) / SCALING_FACTOR;
        console.log("Premium Adjustment: %s", premiumAdjustment);

        uint256 liquidationPrice;
        if (isLong) {
            // For longs: EntryPrice * (1 - (1/leverage)) + Premium Adjustment
            uint256 adjustment = liquidationAdjustment + premiumAdjustment;
            console.log("Final Adjustment (Long): %s", adjustment);

            liquidationPrice = (entryPrice * adjustment) / SCALING_FACTOR;
            console.log("Calculated Liquidation Price (Long): %s", liquidationPrice);

            require(liquidationPrice < entryPrice, "Long liquidation price must be below entry");
        } else {
            // For shorts: EntryPrice * (1 + (1/leverage)) - Premium Adjustment
            uint256 adjustment = SCALING_FACTOR + oneOverLeverage - premiumAdjustment;
            console.log("Final Adjustment (Short): %s", adjustment);

            liquidationPrice = (entryPrice * adjustment) / SCALING_FACTOR;
            console.log("Calculated Liquidation Price (Short): %s", liquidationPrice);

            require(liquidationPrice > entryPrice, "Short liquidation price must be above entry");
        }

        console.log("Final Liquidation Price: %s", liquidationPrice);
        return liquidationPrice;
    }

    /**
     * @dev Calculate PnL for a position
     * @param positionSize Size of the position
     * @param entryPrice Entry price with PRECISION decimals
     * @param currentPrice Current price with PRECISION decimals
     * @param isLong Whether position is long or short
     * @param minimumPrice Minimum valid price
     * @param minimumPositionSize Minimum valid position size
     * @param minimumPnl Minimum PnL to consider (dust threshold)
     * @return PnL value with PRECISION decimals
     */
    function calculatePnL(
        uint256 positionSize,
        uint256 entryPrice,
        uint256 currentPrice,
        bool isLong,
        uint256 minimumPrice,
        uint256 minimumPositionSize,
        uint256 minimumPnl
    ) internal pure returns (int256) {
        // Input validation
        require(entryPrice >= minimumPrice, "Entry price too low");
        require(currentPrice >= minimumPrice, "Current price too low");
        require(positionSize >= minimumPositionSize, "Position too small");

        // Convert to signed integers while maintaining precision
        int256 size = int256(positionSize);
        int256 entry = int256(entryPrice);
        int256 current = int256(currentPrice);

        // Use OpenZeppelin's Math.max for uint256s
        uint256 maxPrice = Math.max(entryPrice, currentPrice);

        // Check for overflow before multiplication
        require(
            size <= type(int256).max / int256(maxPrice),
            "Position size too large"
        );

        int256 pnl;
        if (isLong) {
            // Long position: (currentPrice - entryPrice) * size / entryPrice
            require(
                current >= entry - type(int256).max / size,
                "Price difference too large"
            );
            require(
                current <= entry + type(int256).max / size,
                "Price difference too large"
            );

            int256 priceDiff = current - entry;
            pnl = (size * priceDiff) / entry;
        } else {
            // Short position: (entryPrice - currentPrice) * size / entryPrice
            require(
                entry >= current - type(int256).max / size,
                "Price difference too large"
            );
            require(
                entry <= current + type(int256).max / size,
                "Price difference too large"
            );

            int256 priceDiff = entry - current;
            pnl = (size * priceDiff) / entry;
        }

        // Handle dust amounts
        if (SignedMath.abs(pnl) < uint256(minimumPnl)) {
            return 0;
        }

        return pnl;
    }

    /**
     * @dev Calculate PnL from UserPosition struct
     * @param userPosition The position to calculate PnL for
     * @param currentPrice Current price with PRECISION decimals
     * @param minimumPrice Minimum valid price
     * @param minimumPositionSize Minimum valid position size
     * @param minimumPnl Minimum PnL to consider (dust threshold)
     * @return PnL value with PRECISION decimals
     */
    function calculatePnL(
        StructsLib.UserPosition memory userPosition,
        uint256 currentPrice,
        uint256 minimumPrice,
        uint256 minimumPositionSize,
        uint256 minimumPnl
    ) internal pure returns (int256) {
        return calculatePnL(
            userPosition.positionSize,
            userPosition.entryPrice,
            currentPrice,
            userPosition.longOrShort == StructsLib.Direction.Long,
            minimumPrice,
            minimumPositionSize,
            minimumPnl
        );
    }
}