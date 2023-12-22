// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0 <0.8.0;
pragma abicoder v2;

import "./MarketDataStructure.sol";

interface IFundingLogic {
    function getFunding(address market) external view returns (int256 fundingGrowthGlobalX96);

    function getFundingPayment(address market, uint256 positionId, int256 fundingGrowthGlobalX96) external view returns (int256 fundingPayment);
}

