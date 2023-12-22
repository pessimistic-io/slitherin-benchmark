// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

interface IVolatilityTokenRequester {
    function mintCVIVolatilityToken(uint168 tokenAmount, uint32 maxBuyingPremiumFeePercentage) payable external;
    function burnCVIVolatilityToken(uint168 burnAmount) payable external;
    
    function mintUCVIVolatilityToken(uint168 tokenAmount, uint32 maxBuyingPremiumFeePercentage) payable external;
    function burnUCVIVolatilityToken(uint168 burnAmount) payable external;
}
    
