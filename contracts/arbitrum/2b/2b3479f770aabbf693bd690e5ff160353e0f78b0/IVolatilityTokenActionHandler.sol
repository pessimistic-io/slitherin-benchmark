// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

import "./IPlatformPositionHandler.sol";

interface IVolatilityTokenActionHandler {
    function mintTokensForOwner(address owner, uint168 tokenAmount, uint32 maxBuyingPremiumFeePercentage, uint32 realTimeCVIValue) external returns (uint256 tokensMinted);
    function burnTokensForOwner(address owner,  uint168 burnAmount, uint32 realTimeCVIValue) external returns (uint256 tokensReceived);
    function platform() external view returns (IPlatformPositionHandler);
}

