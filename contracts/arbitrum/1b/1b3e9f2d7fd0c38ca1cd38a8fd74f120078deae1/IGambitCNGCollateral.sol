// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PythStructs} from "./PythStructs.sol";

interface IGambitCNGCollateral {
    function reportPrice(
        uint256 orderId,
        uint256 pairIndex,
        PythStructs.Price memory price
    ) external;
}

