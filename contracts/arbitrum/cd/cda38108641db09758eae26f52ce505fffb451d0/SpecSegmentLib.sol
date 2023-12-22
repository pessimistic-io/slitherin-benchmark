// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./IBotDecisionHelper.sol";
import "./Math.sol";

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
        assert(segId != 0 && segId != specs.numOfBins * 2);
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

