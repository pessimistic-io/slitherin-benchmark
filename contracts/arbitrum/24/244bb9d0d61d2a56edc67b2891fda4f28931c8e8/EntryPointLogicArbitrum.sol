// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ArbGasInfo} from "./ArbGasInfo.sol";

import {EntryPointLogic, IEntryPointLogic, IAutomate, IProtocolFees, Constants} from "./EntryPointLogic.sol";

/// @title EntryPointLogicArbitrum
contract EntryPointLogicArbitrum is EntryPointLogic {
    /// @dev A special arbitrum contract used to calculate the gas that
    /// will be sent to the L1 network
    ArbGasInfo private constant ARB_GAS_ORACLE =
        ArbGasInfo(0x000000000000000000000000000000000000006C);

    /// @notice Sets the addresses of the `automate` and `gelato` upon deployment.
    /// @param automate The instance of GelatoAutomate contract.
    constructor(
        IAutomate automate,
        IProtocolFees protocolFees
    ) EntryPointLogic(automate, protocolFees) {}

    /// @inheritdoc IEntryPointLogic
    function run(
        uint256 workflowKey
    ) external override onlyRoleOrOwner(Constants.EXECUTOR_ROLE) {
        uint256 gasUsed = gasleft();

        _run(workflowKey);
        emit EntryPointRun(msg.sender, workflowKey);

        uint256 l1GasFees = ARB_GAS_ORACLE.getCurrentTxL1GasFees();

        unchecked {
            gasUsed = (gasUsed - gasleft()) * tx.gasprice;
        }

        _transferDittoFee(gasUsed, l1GasFees, false);
    }
}

