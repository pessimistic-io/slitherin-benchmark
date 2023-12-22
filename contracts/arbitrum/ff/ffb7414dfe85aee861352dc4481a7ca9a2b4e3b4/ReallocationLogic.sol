// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import {TransferHelper} from "./TransferHelper.sol";
import "./Perp.sol";
import "./PairLib.sol";
import "./ApplyInterestLib.sol";

library ReallocationLogic {
    function reallocate(DataType.GlobalData storage _globalData, uint256 _pairId)
        external
        returns (bool reallocationHappened, int256 profit)
    {
        // Checks the pair exists
        PairLib.validatePairId(_globalData, _pairId);

        // Updates interest rate related to the pair
        ApplyInterestLib.applyInterestForToken(_globalData.pairs, _pairId);

        DataType.PairStatus storage pairStatus = _globalData.pairs[_pairId];

        Perp.updateRebalanceFeeGrowth(pairStatus, pairStatus.sqrtAssetStatus);

        (reallocationHappened, profit) = Perp.reallocate(pairStatus, pairStatus.sqrtAssetStatus, false);

        if (reallocationHappened) {
            _globalData.rebalanceFeeGrowthCache[PairLib.getRebalanceCacheId(
                _pairId, pairStatus.sqrtAssetStatus.numRebalance
            )] = DataType.RebalanceFeeGrowthCache(
                pairStatus.sqrtAssetStatus.rebalanceFeeGrowthStable,
                pairStatus.sqrtAssetStatus.rebalanceFeeGrowthUnderlying
            );
            pairStatus.sqrtAssetStatus.lastRebalanceTotalSquartAmount = pairStatus.sqrtAssetStatus.totalAmount;
            pairStatus.sqrtAssetStatus.numRebalance++;
        }

        if (profit < 0) {
            address token;

            if (pairStatus.isMarginZero) {
                token = pairStatus.underlyingPool.token;
            } else {
                token = pairStatus.stablePool.token;
            }

            TransferHelper.safeTransferFrom(token, msg.sender, address(this), uint256(-profit));
        }
    }
}

