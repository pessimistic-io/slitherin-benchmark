// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ConfigTypes} from "./ConfigTypes.sol";

interface IStrategyWorker {
    function executeStrategyAction(
        address strategyVaultAddress,
        address depositorAddress
    ) external;
}

