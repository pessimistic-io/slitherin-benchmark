// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

import "./ICVIOracle.sol";

interface IPlatformPositionHandler {
    function openPositionForOwner(address owner, bytes32 referralCode, uint168 tokenAmount, uint32 maxCVI, uint32 maxBuyingPremiumFeePercentage, uint8 leverage, uint32 realTimeCVIValue) external returns (uint168 positionUnitsAmount, uint168 positionedTokenAmount, uint168 openPositionFee, uint168 buyingPremiumFee);
    function closePositionForOwner(address owner, uint168 positionUnitsAmount, uint32 minCVI, uint32 realTimeCVIValue) external returns (uint256 tokenAmount, uint256 closePositionFee, uint256 closingPremiumFee);
    function cviOracle() external view returns (ICVIOracle);
}

