// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

interface INftValidator {
    function validateBorrow(
        address user,
        uint256 amount,
        address gNft,
        uint256 loanId
    ) external view;

    function validateRepay(
        uint256 loanId,
        uint256 repayAmount,
        uint256 borrowAmount
    ) external view;

    function validateAuction(
        address gNft,
        uint256 loanId,
        uint256 bidPrice,
        uint256 borrowAmount
    ) external view;

    function validateRedeem(
        uint256 loanId,
        uint256 repayAmount,
        uint256 bidFine,
        uint256 borrowAmount
    ) external view returns (uint256);

    function validateLiquidate(
        uint256 loanId,
        uint256 borrowAmount,
        uint256 amount
    ) external view returns (uint256, uint256);
}

