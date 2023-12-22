// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ILBFactory} from "./ILBFactory.sol";
import {ILBPair} from "./ILBPair.sol";
import {IERC20} from "./IERC20.sol";

contract JoeV2StateMulticall {
    struct BinInfo {
        uint24 id;
        uint128 reserveX;
        uint128 reserveY;
    }

    struct StateResult {
        ILBPair pair;
        uint24 activeId;
        uint16 binStep;
        uint256 reserve0;
        uint256 reserve1;
        BinInfo[] binInfos;
    }

    function getFullState(
        ILBFactory factory,
        IERC20 tokenX,
        IERC20 tokenY,
        uint256 leftBinLength,
        uint256 rightBinLength
    ) external view returns (StateResult[] memory states) {
        ILBFactory.LBPairInformation[] memory pairsInformation = factory.getAllLBPairs(tokenX, tokenY);
        uint256 numOfAvailablePairs = 0;

        for (uint256 i = 0; i < pairsInformation.length; i++) {
            if (pairsInformation[i].ignoredForRouting) {
                continue;
            } else {
                numOfAvailablePairs++;
            }
        }

        states = new StateResult[](numOfAvailablePairs);
        for (uint256 i = 0; i < pairsInformation.length; i++) {
            ILBFactory.LBPairInformation memory pairInformation = pairsInformation[i];
            if (pairInformation.ignoredForRouting) {
                continue;
            } else {
                ILBPair pair = pairInformation.LBPair;
                uint16 binStep = pairInformation.binStep;
                uint24 activeId = pair.getActiveId();
                StateResult memory state;
                state.pair = pair;
                state.activeId = activeId;
                state.binStep = binStep;
                (state.reserve0, state.reserve1) = pair.getReserves();
                state.binInfos = _getBinInfos(pair, leftBinLength, rightBinLength);
            }
        }
    }

    function _getBinInfos(
        ILBPair pair,
        uint256 leftBinLength,
        uint256 rightBinLength
    ) internal view returns (BinInfo[] memory binInfos) {
        binInfos = new BinInfo[](leftBinLength + rightBinLength);
        uint24 activeId = pair.getActiveId();

        uint24 leftBinId = activeId;
        for (uint256 j = 0; j < leftBinLength; j++) {
            uint24 nextLeftBinId = pair.getNextNonEmptyBin(false, leftBinId);
            (uint128 binReserveX, uint128 binReserveY) = pair.getBin(nextLeftBinId);
            binInfos[leftBinLength - j - 1] = BinInfo({
                id: nextLeftBinId,
                reserveX: binReserveX,
                reserveY: binReserveY
            });
            leftBinId = nextLeftBinId;
        }

        uint24 rightBinId = activeId;
        for (uint256 k = 0; k < rightBinLength; k++) {
            uint24 nextRightBinId = pair.getNextNonEmptyBin(true, rightBinId);
            (uint128 binReserveX, uint128 binReserveY) = pair.getBin(nextRightBinId);
            binInfos[leftBinLength + k] = BinInfo({
                id: nextRightBinId,
                reserveX: binReserveX,
                reserveY: binReserveY
            });
            rightBinId = nextRightBinId;
        }
    }
}

