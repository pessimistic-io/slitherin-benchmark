// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFarmEvent {
    event DepositLiquidity(
        address indexed strategyContract,
        address indexed userAddress,
        uint256 indexed liquidityNftId,
        bool isETH,
        address inputToken,
        uint256 inputAmount,
        uint256 increasedShare,
        uint256 userShareAfterDeposit,
        uint256 increasedToken0Amount,
        uint256 increasedToken1Amount,
        uint256 sendBackToken0Amount,
        uint256 sendBackToken1Amount
    );

    event WithdrawLiquidity(
        address indexed strategyContract,
        address indexed userAddress,
        uint256 indexed liquidityNftId,
        uint256 decreasedShare,
        uint256 userShareAfterWithdraw,
        uint256 userReceivedToken0Amount,
        uint256 userReceivedToken1Amount
    );

    event ClaimReward(
        address indexed strategyContract,
        address indexed userAddress,
        uint256 indexed liquidityNftId,
        uint256 claimedRewardAmount
    );
}

