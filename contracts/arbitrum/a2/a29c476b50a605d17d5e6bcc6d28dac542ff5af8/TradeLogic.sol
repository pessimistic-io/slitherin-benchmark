// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./DataType.sol";
import "./Trade.sol";

library TradeLogic {
    function trade(
        DataType.PairGroup memory _pairGroup,
        DataType.PairStatus storage _pairStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        Perp.UserStatus storage _perpUserStatus,
        int256 _tradeAmount,
        int256 _tradeAmountSqrt
    ) public returns (DataType.TradeResult memory) {
        return Trade.trade(
            _pairGroup, _pairStatus, _rebalanceFeeGrowthCache, _perpUserStatus, _tradeAmount, _tradeAmountSqrt
        );
    }
}

