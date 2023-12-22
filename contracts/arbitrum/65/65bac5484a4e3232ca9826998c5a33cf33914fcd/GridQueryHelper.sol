// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.9;

import "./Math.sol";
import "./SafeCast.sol";
import "./IGrid.sol";
import "./IGridStructs.sol";
import "./BitMath.sol";
import "./BundleMath.sol";
import "./BoundaryMath.sol";
import "./BoundaryBitmap.sol";
import "./FixedPointX128.sol";

/// @title The contract for querying grid data
contract GridQueryHelper {
    using SafeCast for uint256;

    struct MakerBook {
        int24 boundaryLower;
        /// @dev The remaining amount of token1 that can be swapped out,
        /// which is the sum of bundle0 and bundle1
        uint128 makerAmountRemaining;
    }

    /// @notice Tries to settle the order to compute the output amount
    /// @param grid The address of the grid
    /// @param orderId The unique identifier of the order
    /// @return makerAmountOut The amount of token0 or token1 that the maker removed
    /// @return takerAmountOut The amount of swapped out token by the taker
    /// @return takerFeeAmountOut The fee paid by the taker(excluding the protocol fee)
    function trySettleOrder(
        address grid,
        uint256 orderId
    ) external view returns (uint128 makerAmountOut, uint256 takerAmountOut, uint256 takerFeeAmountOut) {
        (uint64 bundleId, , uint128 makerAmountRaw) = IGrid(grid).orders(orderId);
        // GQH_ONF: order not found
        require(makerAmountRaw > 0, "GQH_ONF");

        (
            ,
            ,
            uint128 makerAmountTotal,
            uint128 makerAmountRemaining,
            uint256 takerAmountRemaining,
            uint256 takerFeeAmountRemaining
        ) = IGrid(grid).bundles(bundleId);

        makerAmountOut = Math.mulDiv(makerAmountRaw, makerAmountRemaining, makerAmountTotal).toUint128();

        takerAmountOut = Math.mulDiv(makerAmountRaw, takerAmountRemaining, makerAmountTotal);
        takerFeeAmountOut = Math.mulDiv(makerAmountRaw, takerFeeAmountRemaining, makerAmountTotal);
    }

    /// @notice Gets the maker book of the grid
    /// @param grid The address of the grid
    /// @param zero When zero is true, it represents token0, otherwise it represents token1
    /// @param count The number of boundaries to query
    function makerBooks(address grid, bool zero, uint256 count) external view returns (MakerBook[] memory result) {
        (uint160 priceX96, int24 boundary, , ) = IGrid(grid).slot0();
        int24 resolution = IGrid(grid).resolution();
        int24 boundaryLower = BoundaryMath.getBoundaryLowerAtBoundary(boundary, resolution);
        function(int24) external view returns (uint64, uint64, uint128) boundariesFunc = IGrid(grid).boundaries0;
        function(int16) external view returns (uint256) boundaryBitmapFunc = IGrid(grid).boundaryBitmaps0;
        bool lte = false;
        if (!zero) {
            boundariesFunc = IGrid(grid).boundaries1;
            boundaryBitmapFunc = IGrid(grid).boundaryBitmaps1;
            lte = true;
        }

        result = new MakerBook[](count);
        uint256 i = 0;
        for (; i < count; i++) {
            bool initialized;
            (, , uint128 makerAmountRemaining) = boundariesFunc(boundaryLower);
            (boundaryLower, initialized) = _nextInitializedBoundary(
                boundaryBitmapFunc,
                boundary,
                priceX96,
                makerAmountRemaining > 0,
                resolution,
                boundaryLower,
                lte
            );
            if (!initialized) {
                break;
            }

            (, , makerAmountRemaining) = boundariesFunc(boundaryLower);
            result[i] = MakerBook(boundaryLower, makerAmountRemaining);

            if (lte) {
                boundary =boundaryLower - resolution;
            } else {
                boundary =boundaryLower + resolution;
            }
            priceX96 = BoundaryMath.getPriceX96AtBoundary(boundary);
        }
        uint256 newCount = i;
        if (newCount != count) {
            MakerBook[] memory shrinkResult = new MakerBook[](newCount);
            for (uint256 j = 0; j < newCount; j++) {
                shrinkResult[j] = result[j];
            }
            return shrinkResult;
        }
    }

    function _nextInitializedBoundary(
        function(int16) external view returns (uint256) boundaryBitmapFunc,
        int24 boundary,
        uint160 priceX96,
        bool currentBoundaryInitialized,
        int24 resolution,
        int24 boundaryLower,
        bool lte
    ) internal view returns (int24 next, bool initialized) {
        int24 boundaryUpper = boundaryLower + resolution;
        if (currentBoundaryInitialized) {
            uint160 boundaryLowerPriceX96 = BoundaryMath.getPriceX96AtBoundary(boundaryLower);
            uint160 boundaryUpperPriceX96 = BoundaryMath.getPriceX96AtBoundary(boundaryUpper);
            if ((lte && boundaryLowerPriceX96 < priceX96) || (!lte && boundaryUpperPriceX96 > priceX96)) {
                return (boundaryLower, true);
            }
        }

        boundary = !lte && boundaryUpper == boundary ? boundaryLower : boundary;
        while (BoundaryMath.isInRange(boundary) && !initialized) {
            (next, initialized) = _nextInitializedBoundaryWithinOneWord(boundaryBitmapFunc, boundary, resolution, lte);
            boundary = next;
        }
    }

    function _nextInitializedBoundaryWithinOneWord(
        function(int16) external view returns (uint256) boundaryBitmapFunc,
        int24 boundary,
        int24 resolution,
        bool lte
    ) internal view returns (int24 next, bool initialized) {
        int24 compressed = boundary / resolution;

        if (lte) {
            (int16 wordPos, uint8 bitPos) = BoundaryBitmap.position(compressed - 1);
            uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
            uint256 masked = boundaryBitmapFunc(wordPos) & mask;

            initialized = masked != 0;
            next = initialized
                ? (compressed - 1 - int24(uint24(bitPos - BitMath.mostSignificantBit(masked)))) * resolution
                : (compressed - 1 - int24(uint24(bitPos))) * resolution;
        } else {
            if (boundary < 0 && boundary % resolution != 0) {
                --compressed;
            }

            (int16 wordPos, uint8 bitPos) = BoundaryBitmap.position(compressed + 1);
            uint256 mask = ~((1 << bitPos) - 1);
            uint256 masked = boundaryBitmapFunc(wordPos) & mask;

            initialized = masked != 0;
            next = initialized
                ? (compressed + 1 + int24(uint24(BitMath.leastSignificantBit(masked) - bitPos))) * resolution
                : (compressed + 1 + int24(uint24(type(uint8).max - bitPos))) * resolution;
        }
    }
}

