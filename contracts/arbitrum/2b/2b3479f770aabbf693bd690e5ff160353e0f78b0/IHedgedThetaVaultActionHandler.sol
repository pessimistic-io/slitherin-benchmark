// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

import "./IVolatilityTokenActionHandler.sol";

interface IHedgedThetaVaultActionHandler {
    function depositForOwner(address owner, uint168 tokenAmount, uint32 realTimeCVIValue, bool shouldStake) external returns (uint256 hedgedThetaTokensMinted);
    function withdrawForOwner(address owner, uint168 hedgedThetaTokenAmount, uint32 realTimeCVIValue) external returns (uint256 tokenWithdrawnAmount);
}

