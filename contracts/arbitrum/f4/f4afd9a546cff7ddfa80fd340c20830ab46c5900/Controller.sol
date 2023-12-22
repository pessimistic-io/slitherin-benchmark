// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title   Strategy Controller.
 * @author  André Ferreira

  * @dev    VERSION: 1.0
 *          DATE:    2023.08.29
*/

import {Ownable} from "./Ownable.sol";
import {StrategyWorker} from "./StrategyWorker.sol";

contract Controller is Ownable {
    // Only Callable by Pulsar Deployer EOA Address
    function triggerStrategyAction(
        address _strategyWorkerAddress,
        address _strategyVaultAddress,
        address _depositorAddress
    ) public onlyOwner {
        StrategyWorker strategyWorker = StrategyWorker(_strategyWorkerAddress);
        strategyWorker.executeStrategyAction(
            _strategyVaultAddress,
            _depositorAddress
        );
    }
}

