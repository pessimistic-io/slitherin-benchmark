// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Epoch} from "./Epoch.sol";

interface ICouponPositionHook {
    function hook(uint256 positionId, uint256 collateralAmount, uint256 debtAmount, Epoch expiredWith) external;
}

