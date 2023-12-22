// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

import "./IThetaVault.sol";

interface IMegaThetaVault {

    event Deposit(address indexed account, uint256 totalUSDCAmount, uint256 mintedCVIThetaTokens, uint256 mintedUCVIThetaTokens, uint256 mintedMegaThetaTokens);
    event Withdraw(address indexed account, uint256 totalUSDCAmount,  uint256 burnedCVIThetaTokens,  uint256 burnedUCVIThetaTokens,  uint256 burnedMegaThetaTokens);

    function depositForOwner(address owner, uint168 tokenAmount, uint32 realTimeCVIValue) external returns (uint256 megaThetaTokensMinted);
    function withdrawForOwner(address owner, uint168 thetaTokenAmount, uint32 realTimeCVIValue) external returns (uint256 tokenWithdrawnAmount);

    function deposit(uint168 tokenAmount, uint32 balanceCVIValue) external returns (uint256 megaThetaTokensMinted);
    function withdraw(uint168 thetaTokenAmount, uint32 burnCVIValue, uint32 withdrawCVIValue) external returns (uint256 tokenWithdrawnAmount);

    function totalBalance(uint32 balanceCVIValue) external view returns (uint256 balance, uint256 cviBalance, uint256 ucviBalance);
    function calculateOIBalance() external view returns (uint256 oiBalance);
    function calculateMaxOIBalance() external view returns (uint256 maxOIBalance);

    function thetaVault() external view returns (IThetaVault);
}

