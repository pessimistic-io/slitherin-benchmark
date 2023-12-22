// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title   Gelato Automate Resolver.
 * @author  Pulsar Finance
 * @dev     VERSION: 1.0
 *          DATE:    2023.09.20
 */

import {IController} from "./IController.sol";
import {AutomatedVaultERC4626} from "./AutomatedVaultERC4626.sol";
import {IAutomatedVaultsFactory} from "./IAutomatedVaultsFactory.sol";

contract Resolver {
    address public strategyWorkerAddress;

    IAutomatedVaultsFactory public automatedVaultsFactory;

    constructor(
        address _automatedVaultsFactoryAddress,
        address _strategyWorkerAddress
    ) {
        automatedVaultsFactory = IAutomatedVaultsFactory(
            _automatedVaultsFactoryAddress
        );
        strategyWorkerAddress = _strategyWorkerAddress;
    }

    function checker() external view returns (bool, bytes memory) {
        address[] memory allVaults = automatedVaultsFactory
            .getAllVaultsPerStrategyWorker(strategyWorkerAddress);
        bool canExec;
        bytes memory execPayload;
        uint256 _allVaultsLength = allVaults.length;

        for (uint256 i; i < _allVaultsLength; ) {
            AutomatedVaultERC4626 vault = AutomatedVaultERC4626(allVaults[i]);
            uint256 _vaulDepositorsLength = vault.allDepositorsLength();
            for (uint256 j; j < _vaulDepositorsLength; ) {
                address depositorAddress = vault.getDepositorAddress(j);
                uint256 depositorTotalPeriodicBuyAmount = vault
                    .getDepositorTotalPeriodicBuyAmount(depositorAddress);
                execPayload = abi.encodeWithSelector(
                    IController.triggerStrategyAction.selector,
                    strategyWorkerAddress,
                    address(vault),
                    depositorAddress
                );

                canExec = _canExec(
                    vault.lastUpdateOf(depositorAddress),
                    vault.getUpdateFrequencyTimestamp(),
                    vault.maxWithdraw(depositorAddress),
                    vault.allowance(depositorAddress, strategyWorkerAddress),
                    depositorTotalPeriodicBuyAmount,
                    vault.convertToShares(depositorTotalPeriodicBuyAmount)
                );

                if (canExec) {
                    return (canExec, execPayload);
                }
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
        return (canExec, execPayload);
    }

    function _canExec(
        uint256 lastUpdateOf,
        uint256 updateFrequencyTimestamp,
        uint256 depositorBalance,
        uint256 depositorAllowance,
        uint256 depositorTotalPeriodicBuyAmount,
        uint256 depositorTotalPeriodicBuyAmountShares
    ) private view returns (bool) {
        return (((block.timestamp >=
            (lastUpdateOf + updateFrequencyTimestamp)) || lastUpdateOf == 0) &&
            (depositorBalance >= depositorTotalPeriodicBuyAmount) &&
            (depositorAllowance >= depositorTotalPeriodicBuyAmountShares));
    }
}

