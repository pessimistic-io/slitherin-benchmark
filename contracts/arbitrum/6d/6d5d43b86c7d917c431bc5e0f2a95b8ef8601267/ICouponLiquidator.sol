// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ERC20PermitParams} from "./PermitParams.sol";

interface ICouponLiquidator {
    error CollateralSwapFailed(string reason);

    function liquidate(
        uint256 positionId,
        uint256 swapAmount,
        bytes calldata swapData,
        uint256 allowedSupplementaryAmount,
        address recipient
    ) external payable;
}

