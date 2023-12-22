// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./IUniswapV3PoolMinimum.sol";

library UniswapV3PoolTicksCounter {
    function countInitializedTicksCrossed(
        IUniswapV3PoolMinimum self,
        int24 tickBefore,
        int24 tickAfter
    ) internal view returns (uint32 initializedTicksCrossed) {
        int16 wordPosLower;
        int16 wordPosHigher;
        uint8 bitPosLower;
        uint8 bitPosHigher;
        bool tickBeforeInitialized;
        bool tickAfterInitialized;

        {
            int16 wordPos = int16((tickBefore / self.tickSpacing()) >> 8);
            uint8 bitPos = uint8(uint24(tickBefore / self.tickSpacing()) % 256);

            int16 wordPosAfter = int16((tickAfter / self.tickSpacing()) >> 8);
            uint8 bitPosAfter = uint8(uint24(tickAfter / self.tickSpacing()) % 256);

            tickAfterInitialized =
                ((self.tickBitmap(wordPosAfter) & (1 << bitPosAfter)) > 0) &&
                ((tickAfter % self.tickSpacing()) == 0) &&
                (tickBefore > tickAfter);

            tickBeforeInitialized =
                ((self.tickBitmap(wordPos) & (1 << bitPos)) > 0) &&
                ((tickBefore % self.tickSpacing()) == 0) &&
                (tickBefore < tickAfter);

            if (wordPos < wordPosAfter || (wordPos == wordPosAfter && bitPos <= bitPosAfter)) {
                wordPosLower = wordPos;
                bitPosLower = bitPos;
                wordPosHigher = wordPosAfter;
                bitPosHigher = bitPosAfter;
            } else {
                wordPosLower = wordPosAfter;
                bitPosLower = bitPosAfter;
                wordPosHigher = wordPos;
                bitPosHigher = bitPos;
            }
        }

        uint256 mask = type(uint256).max << bitPosLower;
        while (wordPosLower <= wordPosHigher) {
            if (wordPosLower == wordPosHigher) mask = mask & (type(uint256).max >> (255 - bitPosHigher));

            uint256 masked = self.tickBitmap(wordPosLower) & mask;
            initializedTicksCrossed += countOneBits(masked);
            wordPosLower++;
            mask = type(uint256).max;
        }

        if (tickAfterInitialized) initializedTicksCrossed -= 1;

        if (tickBeforeInitialized) initializedTicksCrossed -= 1;

        return initializedTicksCrossed;
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

