// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./RequestControllerStorage.sol";
import "./CommonModifiers.sol";

abstract contract RequestControllerModifiers is
    RequestControllerStorage,
    CommonModifiers
{

    modifier onlyMid() {
        if (msg.sender != address(middleLayer)) revert OnlyMiddleLayer();
        _;
    }
}

