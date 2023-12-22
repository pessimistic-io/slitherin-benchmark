// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IController} from "./IController.sol";

interface IBorrowController is IController {
    error CollateralSwapFailed(string reason);
    error InvalidDebtAmount();

    function borrow(
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 maxPayInterest,
        uint16 loanEpochs,
        ERC20PermitParams calldata collateralPermitParams
    ) external payable;

    function borrowMore(
        uint256 positionId,
        uint256 amount,
        uint256 maxPayInterest,
        PermitSignature calldata positionPermitParams
    ) external;

    function addCollateral(
        uint256 positionId,
        uint256 amount,
        PermitSignature calldata positionPermitParams,
        ERC20PermitParams calldata collateralPermitParams
    ) external payable;

    function removeCollateral(uint256 positionId, uint256 amount, PermitSignature calldata positionPermitParams)
        external;

    function extendLoanDuration(
        uint256 positionId,
        uint16 epochs,
        uint256 maxPayInterest,
        PermitSignature calldata positionPermitParams,
        ERC20PermitParams calldata debtPermitParams
    ) external payable;

    function shortenLoanDuration(
        uint256 positionId,
        uint16 epochs,
        uint256 minEarnInterest,
        PermitSignature calldata positionPermitParams
    ) external;

    function repay(
        uint256 positionId,
        uint256 amount,
        uint256 minEarnInterest,
        PermitSignature calldata positionPermitParams,
        ERC20PermitParams calldata debtPermitParams
    ) external payable;
}

