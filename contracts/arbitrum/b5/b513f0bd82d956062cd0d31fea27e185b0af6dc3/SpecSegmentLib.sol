// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./IBotDecisionHelper.sol";
import "./Math.sol";

// Library convention:
// BinId: the index of the bin as defined in the docs [-4 ... 4], could be [-3 ... 5] in case
// botState.buyBins is decreased
// SegId: the index of the bin shifted botState.buyBins to the right [0 ... 8], always remains
// in this range

// This library aims to implement:
// - The binId <-> segId <-> iy conversion
// - Calculate implied yield related information for bin/seg

library SpecSegmentLib {
    using Math for uint256;
    using Math for int256;

    function getSegLength(TradingSpecs memory specs) internal pure returns (uint256) {
        return (specs.sellYtIy - specs.buyYtIy) / (2 * specs.numOfBins);
    }

    function getMidIyOfSeg(
        TradingSpecs memory specs,
        uint256 segId
    ) internal pure returns (uint256) {
        // This function is called when the currentBin sees the segId bin as the target
        // As so, the leftmost and rightmost bin should not be considered
        assert(segId != 0 && segId != specs.numOfBins * 2 + 1);

        uint256 length = getSegLength(specs);
        return specs.buyYtIy + length * (segId - 1) + length / 2;
    }

    function getSegIdForIy(
        TradingSpecs memory specs,
        uint256 iy
    ) internal pure returns (uint256) {
        if (iy < specs.buyYtIy) {
            return 0;
        }
        if (iy > specs.sellYtIy) {
            return 2 * specs.numOfBins + 1;
        }
        return (iy - specs.buyYtIy) / getSegLength(specs) + 1;
    }

    function convertSegIdToBinId(
        BotState memory botState,
        uint256 segId
    ) internal pure returns (int256) {
        int256 binId = segId.Int() - botState.buyBins.Int();
        if (binId >= 1) binId--;
        return binId;
    }

    function convertBinIdToSegId(
        BotState memory botState,
        int256 binId
    ) internal pure returns (uint256) {
        // It's impossible to determine the segId of two middle bins as they share the binId value of 0
        // In practice, we don't need to take any action in case currentBin = 0, so this case can be ignored
        assert(binId != 0); 

        if (binId >= 1) binId++;
        return (binId + botState.buyBins.Int()).Uint();
    }

    function getBinIdForIy(
        TradingSpecs memory specs,
        BotState memory botState,
        uint256 iy
    ) internal pure returns (int256) {
        return convertSegIdToBinId(botState, getSegIdForIy(specs, iy));
    }
}

