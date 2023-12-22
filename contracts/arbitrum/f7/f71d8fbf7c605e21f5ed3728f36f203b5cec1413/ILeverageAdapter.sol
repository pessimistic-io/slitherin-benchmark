// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IController} from "./IController.sol";

interface ILeverageAdapter is IController {
    error CollateralSwapFailed(string reason);

    function leverage(
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 maxPayInterest,
        uint16 loanEpochs,
        bytes memory swapData,
        ERC20PermitParams calldata collateralPermitParams
    ) external payable;

    function leverageMore(
        uint256 positionId,
        uint256 collateralAmount,
        uint256 debtAmount,
        uint256 maxPayInterest,
        bytes memory swapData,
        PermitSignature calldata positionPermitParams,
        ERC20PermitParams calldata collateralPermitParams
    ) external payable;
}

