// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./DataType.sol";
import "./Constants.sol";
import "./Perp.sol";

library DebtCalculator {
    function calculateDebtValue(
        DataType.AssetStatus memory _underlyingAssetStatus,
        Perp.UserStatus memory _perpUserStatus,
        uint160 _sqrtPrice
    ) internal pure returns (uint256) {
        (,, uint256 debtAmountUnderlying, uint256 debtAmountStable) = Perp.getAmounts(
            _underlyingAssetStatus.sqrtAssetStatus, _perpUserStatus, _underlyingAssetStatus.isMarginZero, _sqrtPrice
        );

        return _calculateDebtValue(_sqrtPrice, debtAmountUnderlying, debtAmountStable);
    }

    function _calculateDebtValue(uint256 _sqrtPrice, uint256 debtAmountUnderlying, uint256 debtAmountStable)
        internal
        pure
        returns (uint256)
    {
        uint256 price = (_sqrtPrice * _sqrtPrice) >> Constants.RESOLUTION;

        return ((debtAmountUnderlying * price) >> Constants.RESOLUTION) + debtAmountStable;
    }
}

