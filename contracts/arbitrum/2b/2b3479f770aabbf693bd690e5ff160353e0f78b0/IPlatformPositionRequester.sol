// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

interface IPlatformPositionRequester {
    function openCVIPlatformPosition(bytes32 referralCode, uint168 tokenAmount, uint32 maxCVI, uint32 maxBuyingPremiumFeePercentage, uint8 leverage) payable external; 
    function closeCVIPlatformPosition(uint168 positionUnitsAmount, uint32 minCVI) payable external;

    function openUCVIPlatformPosition(bytes32 referralCode, uint168 tokenAmount, uint32 maxCVI, uint32 maxBuyingPremiumFeePercentage, uint8 leverage) payable external; 
    function closeUCVIPlatformPosition(uint168 positionUnitsAmount, uint32 minCVI) payable external;

    function openReversePlatformPosition(bytes32 referralCode, uint168 tokenAmount, uint32 maxCVI, uint32 maxBuyingPremiumFeePercentage, uint8 leverage) payable external; 
    function closeReversePlatformPosition(uint168 positionUnitsAmount, uint32 minCVI) payable external;
}
    
