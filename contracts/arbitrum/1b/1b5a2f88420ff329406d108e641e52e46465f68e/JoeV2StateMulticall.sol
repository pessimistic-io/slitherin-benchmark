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
        address tokenX;
        address tokenY;
        uint24 activeId;
        uint16 binStep;
        uint256 reserve0;
        uint256 reserve1;
        uint256 totalFee;
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
                state.tokenX = address(pair.getTokenX());
                state.tokenY = address(pair.getTokenY());
                state.activeId = activeId;
                state.binStep = binStep;
                (state.reserve0, state.reserve1) = pair.getReserves();
                {
                    (uint16 baseFactor, , , , uint24 variableFeeControl, , ) = pair.getStaticFeeParameters();
                    (uint24 volatilityAccumulator, , , ) = pair.getVariableFeeParameters();
                    uint256 baseFee = uint256(baseFactor) * binStep * 1e10;
                    uint256 variableFee;
                    if (variableFeeControl != 0) {
                        uint256 prod = uint256(volatilityAccumulator) * binStep;
                        variableFee = (prod * prod * variableFeeControl + 99) / 100;
                    }
                    state.totalFee = baseFee + variableFee;
                }
                state.binInfos = _getBinInfos(pair, leftBinLength, rightBinLength);
                states[i] = state;
            }
        }
    }

    function _getBinInfo( ILBPair pair, uint24 id) internal view returns (BinInfo memory) {
        (uint128 binReserveX, uint128 binReserveY) = pair.getBin(id);
        return BinInfo({
            id: id,
            reserveX: binReserveX,
            reserveY: binReserveY
        });
    }

    function _getBinInfos(
        ILBPair pair,
        uint256 leftBinLength,
        uint256 rightBinLength
    ) internal view returns (BinInfo[] memory binInfos) {
        binInfos = new BinInfo[](leftBinLength + rightBinLength + 1);
        uint24 activeId = pair.getActiveId();
        binInfos[leftBinLength] = _getBinInfo(pair, activeId);

        uint24 leftBinId = activeId;
        for (uint256 i = 0; i < leftBinLength; i++) {
            uint24 nextLeftBinId = pair.getNextNonEmptyBin(false, leftBinId);
            binInfos[leftBinLength - i - 1] = _getBinInfo(pair, nextLeftBinId);
            leftBinId = nextLeftBinId;
        }

        uint24 rightBinId = activeId;
        for (uint256 i = 0; i < rightBinLength; i++) {
            uint24 nextRightBinId = pair.getNextNonEmptyBin(true, rightBinId);
            binInfos[leftBinLength + i + 1] = _getBinInfo(pair, nextRightBinId);
            rightBinId = nextRightBinId;
        }
    }
}

