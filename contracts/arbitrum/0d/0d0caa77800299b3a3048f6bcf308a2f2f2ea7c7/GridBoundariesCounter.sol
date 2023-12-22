// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./IGrid.sol";
import "./BoundaryBitmap.sol";

library GridBoundariesCounter {
    using BoundaryBitmap for int24;

    struct CountInitializedBoundariesCrossedParameters {
        IGrid grid;
        bool zeroForOne;
        uint160 priceX96Before;
        int24 boundaryBefore;
        int24 boundaryLowerBefore;
        uint160 priceX96After;
        int24 boundaryAfter;
        int24 boundaryLowerAfter;
    }

    /// @dev This function counts the number of initialized boundaries that would incur a gas cost
    /// between boundaryBefore and boundaryAfter. When boundaryBefore and/or boundaryAfter is initialized,
    /// the logic over whether we should count them depends on the direction of the swap and the location
    /// of the boundary corresponding to price.
    /// If we are swapping upwards(boundaryAfter > boundaryBefore) we want to count boundaryBefore
    /// if the priceBefore is lower than boundaryUpperPriceBefore. We don't want to count boundaryBefore
    /// if the priceBefore is equal to boundaryUpperPriceBefore.
    /// Similarly, if we are swapping downwards(boundaryBefore > boundaryAfter) we want to count boundaryBefore if
    /// the priceBefore is higher than boundaryLowerPriceBefore. We don't want to count boundaryBefore if the
    /// priceBefore is equal to boundaryLowerPriceBefore.
    /// For boundaryAfter, use logic similar to the above.
    function countInitializedBoundariesCrossed(
        CountInitializedBoundariesCrossedParameters memory parameters
    ) internal view returns (uint32 initializedBoundariesCrossed) {
        int16 wordPosLower;
        int16 wordPosHigher;
        uint8 bitPosLower;
        uint8 bitPosHigher;
        bool boundaryBeforeInitialized;
        bool countBoundaryBefore;
        bool boundaryAfterInitialized;
        bool countBoundaryAfter;

        {
            int24 resolution = parameters.grid.resolution();

            if (parameters.zeroForOne) {
                /// We are swapping downwards when zeroForOne is true.
                /// wordPosLower = wordPosAfter;
                /// bitPosLower = bitPosAfter;
                /// wordPosHigher = wordPosBefore;
                /// bitPosHigher = bitPosBefore;
                (wordPosLower, bitPosLower) = (parameters.boundaryLowerAfter / resolution).position();
                (wordPosHigher, bitPosHigher) = (parameters.boundaryLowerBefore / resolution).position();
                (
                    boundaryBeforeInitialized,
                    countBoundaryBefore,
                    boundaryAfterInitialized,
                    countBoundaryAfter
                ) = whetherCountZeroForOne(
                    parameters,
                    resolution,
                    wordPosHigher,
                    bitPosHigher,
                    wordPosLower,
                    bitPosLower
                );
            } else {
                /// We are swapping upwards when zeroForOne is false.
                /// wordPosLower = wordPosBefore;
                /// bitPosLower = bitPosBefore;
                /// wordPosHigher = wordPosAfter;
                /// bitPosHigher = bitPosAfter;
                (wordPosLower, bitPosLower) = (parameters.boundaryLowerBefore / resolution).position();
                (wordPosHigher, bitPosHigher) = (parameters.boundaryLowerAfter / resolution).position();
                (
                    boundaryBeforeInitialized,
                    countBoundaryBefore,
                    boundaryAfterInitialized,
                    countBoundaryAfter
                ) = whetherCountOneForZero(
                    parameters,
                    resolution,
                    wordPosLower,
                    bitPosLower,
                    wordPosHigher,
                    bitPosHigher
                );
            }
        }

        initializedBoundariesCrossed = countAllInitializedBoundaries(
            parameters.grid,
            parameters.zeroForOne,
            wordPosLower,
            wordPosHigher,
            bitPosLower,
            bitPosHigher
        );

        if (boundaryAfterInitialized && !countBoundaryAfter) initializedBoundariesCrossed -= 1;

        if (boundaryBeforeInitialized && !countBoundaryBefore) initializedBoundariesCrossed -= 1;

        return initializedBoundariesCrossed;
    }

    function whetherCountOneForZero(
        CountInitializedBoundariesCrossedParameters memory parameters,
        int24 resolution,
        int16 wordPosBefore,
        uint8 bitPosBefore,
        int16 wordPosAfter,
        uint8 bitPosAfter
    )
        private
        view
        returns (
            bool boundaryBeforeInitialized,
            bool countBoundaryBefore,
            bool boundaryAfterInitialized,
            bool countBoundaryAfter
        )
    {
        int24 boundaryUpperBefore = parameters.boundaryLowerBefore + resolution;
        uint160 boundaryUpperPriceX96Before = BoundaryMath.isInRange(boundaryUpperBefore)
            ? BoundaryMath.getPriceX96AtBoundary(boundaryUpperBefore)
            : 0;
        boundaryBeforeInitialized = (parameters.grid.boundaryBitmaps0(wordPosBefore) & (1 << bitPosBefore)) > 0;
        countBoundaryBefore = boundaryBeforeInitialized && (parameters.priceX96Before < boundaryUpperPriceX96Before);

        uint160 boundaryLowerPriceX96After = BoundaryMath.getPriceX96AtBoundary(parameters.boundaryLowerAfter);
        boundaryAfterInitialized = (parameters.grid.boundaryBitmaps0(wordPosAfter) & (1 << bitPosAfter)) > 0;
        countBoundaryAfter = boundaryAfterInitialized && (parameters.priceX96After > boundaryLowerPriceX96After);

        return (boundaryBeforeInitialized, countBoundaryBefore, boundaryAfterInitialized, countBoundaryAfter);
    }

    function whetherCountZeroForOne(
        CountInitializedBoundariesCrossedParameters memory parameters,
        int24 resolution,
        int16 wordPosBefore,
        uint8 bitPosBefore,
        int16 wordPosAfter,
        uint8 bitPosAfter
    )
        private
        view
        returns (
            bool boundaryBeforeInitialized,
            bool countBoundaryBefore,
            bool boundaryAfterInitialized,
            bool countBoundaryAfter
        )
    {
        uint160 boundaryLowerPriceX96Before = BoundaryMath.getPriceX96AtBoundary(parameters.boundaryLowerBefore);
        boundaryBeforeInitialized = (parameters.grid.boundaryBitmaps1(wordPosBefore) & (1 << bitPosBefore)) > 0;
        countBoundaryBefore = boundaryBeforeInitialized && (parameters.priceX96Before > boundaryLowerPriceX96Before);

        int24 boundaryUpperAfter = parameters.boundaryLowerAfter + resolution;
        uint160 boundaryUpperPriceX96After = BoundaryMath.isInRange(boundaryUpperAfter)
            ? BoundaryMath.getPriceX96AtBoundary(boundaryUpperAfter)
            : 0;
        boundaryAfterInitialized = ((parameters.grid.boundaryBitmaps1(wordPosAfter) & (1 << bitPosAfter)) > 0);
        countBoundaryAfter = boundaryAfterInitialized && (parameters.priceX96After < boundaryUpperPriceX96After);

        return (boundaryBeforeInitialized, countBoundaryBefore, boundaryAfterInitialized, countBoundaryAfter);
    }

    function countAllInitializedBoundaries(
        IGrid grid,
        bool zeroForOne,
        int16 wordPosLower,
        int16 wordPosHigher,
        uint8 bitPosLower,
        uint8 bitPosHigher
    ) private view returns (uint32 initializedBoundariesCrossed) {
        // Count the number of initialized boundaries crossed by iterating through the boundary bitmap.
        // Our first mask should include the lower boundary and everything to its left.
        uint256 mask = type(uint256).max << bitPosLower;
        while (wordPosLower <= wordPosHigher) {
            // If we are on the final boundary bitmap page, ensure we only count up to our ending boundary.
            if (wordPosLower == wordPosHigher) mask = mask & (type(uint256).max >> (255 - bitPosHigher));

            uint256 masked = zeroForOne
                ? (grid.boundaryBitmaps1(wordPosLower) & mask)
                : (grid.boundaryBitmaps0(wordPosLower) & mask);
            initializedBoundariesCrossed += countOneBits(masked);
            wordPosLower++;
            // Reset our mask so we consider all bits on the next iteration.
            mask = type(uint256).max;
        }
        return initializedBoundariesCrossed;
    }

    function countOneBits(uint256 x) private pure returns (uint16) {
        uint16 bits = 0;
        unchecked {
            while (x != 0) {
                bits++;
                x &= (x - 1);
            }
        }
        return bits;
    }
}

