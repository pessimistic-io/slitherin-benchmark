// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./ScaledAsset.sol";
import "./DataType.sol";

library PairLib {
    function validatePairId(DataType.GlobalData storage _globalData, uint256 _pairId) internal view {
        require(0 < _pairId && _pairId < _globalData.pairsCount, "PAIR0");
    }

    function checkPairBelongsToPairGroup(DataType.PairStatus memory _pair, uint256 _pairGroupId) internal pure {
        require(_pair.pairGroupId == _pairGroupId, "PAIR1");
    }

    function getRebalanceCacheId(uint256 _pairId, uint64 _rebalanceId) internal pure returns (uint256) {
        return _pairId * type(uint64).max + _rebalanceId;
    }
}

