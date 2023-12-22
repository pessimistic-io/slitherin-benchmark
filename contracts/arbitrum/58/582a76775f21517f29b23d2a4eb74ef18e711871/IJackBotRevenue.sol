// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IJackBotRevenue {
  function swapBack(
    uint256 contractBalance,
    uint256 tokensForBankroll,
    uint256 tokensForLiquidity,
    uint256 tokensForRevShare,
    uint256 tokensForTeam,
    uint256 swapTokensAtAmount,
    address teamWallet,
    address revShareWallet,
    address bankrollWallet
  ) external;
}

