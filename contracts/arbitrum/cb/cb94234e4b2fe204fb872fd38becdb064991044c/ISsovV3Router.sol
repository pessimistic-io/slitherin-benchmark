//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {ISsovV3} from "./ISsovV3.sol";

interface ISsovV3Router {
    function multideposit(
        uint256[] calldata _strikeIndices,
        uint256[] calldata _amounts,
        address _to,
        ISsovV3 _ssov
    ) external;
}

