// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IController} from "./IController.sol";

interface IRepayAdapter is IController {
    error CollateralSwapFailed(string reason);

    function repayWithCollateral(
        uint256 positionId,
        uint256 sellCollateralAmount,
        uint256 minRepayAmount,
        bytes memory swapData,
        PermitSignature calldata positionPermitParams
    ) external;
}

