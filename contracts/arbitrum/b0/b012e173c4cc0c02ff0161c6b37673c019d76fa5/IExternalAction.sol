// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "./CircomData.sol";

interface IExternalAction {
    function runAction(
        CircomData memory circomData,
        bytes memory metadata
    ) external;
}

