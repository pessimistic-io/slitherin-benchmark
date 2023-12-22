// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

interface IBinaryVaultBetFacet {
    function onPlaceBet(
        uint256 amount,
        address from,
        uint256 endTime,
        uint8 position,
        bool creditUsed,
        uint256[] memory creditTokenIds,
        uint256[] memory creditTokenAmounts,
        address feeWallet,
        uint256 feeAmount
    ) external;

    function onRoundExecuted(
        uint256 wonAmount,
        uint256 loseAmount,
        uint256 wonCreditAmount,
        uint256 loseCreditAmount
    ) external;

    function claimBettingRewards(
        address user,
        uint256 amount,
        bool isRefund,
        bool creditUsed,
        uint256[] memory creditTokenIds,
        uint256[] memory creditTokenAmounts
    ) external returns (uint256);
}

