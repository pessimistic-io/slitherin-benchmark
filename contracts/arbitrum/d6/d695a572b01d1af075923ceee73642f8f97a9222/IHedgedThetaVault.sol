// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

interface IHedgedThetaVault {

    event HedgedDeposit(address indexed account, uint168 totalUSDCAmount, uint168 holdingsAmount, uint256 mintedHedgedThetaTokens);
    event HedgedWithdraw(address indexed account, uint256 totalUSDCAmount, uint256 burnedHedgedThetaTokens);

    function depositForOwner(address owner, uint168 tokenAmount, uint32 realTimeCVIValue, bool shouldStake) external returns (uint256 hedgedThetaTokensMinted);
    function withdrawForOwner(address owner, uint168 hedgedThetaTokenAmount, uint32 realTimeCVIValue) external returns (uint256 tokenWithdrawnAmount);

    function totalBalance(uint32 megaThetaVaultBalanceCVI, uint32 reversePlatformBalanceCVI) external view returns (uint256 balance, uint256 inversePlatformLiquidity, uint256 holdings, uint256 megaThetaVaultBalance);
}

