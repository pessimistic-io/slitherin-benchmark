//SPDX-License-Identifier: ISC
pragma solidity ^0.8.9;

import "./SafeMath.sol";
import "./ConfigurationParam.sol";

library VaultFeeCalculation {
    /// @dev The vault charges 2% management fee, which is 100*2%*(5/365) = 0.027
    function ManagementFeeCalculation(
        uint256 principal,
        uint256 day,
        uint256 manageFee
    ) internal pure returns (uint256) {
        return SafeMath.div(SafeMath.mul(SafeMath.mul(principal, manageFee), day), 365e6);
    }

    /// @dev Thue vault charges 10% of profit, which is (120-100)*10% = 2
    function ProfitFeeCalculation(
        uint256 grossProfit,
        uint256 principal,
        uint256 profitFee
    ) internal pure returns (uint256) {
        uint256 netProfit = SafeMath.sub(grossProfit, principal);
        return SafeMath.div(SafeMath.mul(netProfit, profitFee), ConfigurationParam.PERCENTILE);
    }

    /// @dev Profit calculation
    function profitCalculation(
        uint256 initAmountValue,
        uint256 latestAmountValue,
        uint256 principal
    ) internal pure returns (uint256) {
        return SafeMath.div(SafeMath.mul(latestAmountValue, principal), initAmountValue);
    }
}

