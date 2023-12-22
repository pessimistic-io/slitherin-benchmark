// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ArbGasInfo} from "./ArbGasInfo.sol";

import {ExecutionLogic, IExecutionLogic, IProtocolFees} from "./ExecutionLogic.sol";

/// @title ExecutionLogicArbitrum
/// @notice This contract holds the logic for executing any transactions
/// to the target contract or batch txs in multicall
contract ExecutionLogicArbitrum is ExecutionLogic {
    /// @dev A special arbitrum contract used to calculate the gas that
    /// will be sent to the L1 network
    ArbGasInfo private constant ARB_GAS_ORACLE =
        ArbGasInfo(0x000000000000000000000000000000000000006C);

    constructor(IProtocolFees protocolFees) ExecutionLogic(protocolFees) {}

    // =========================
    // Main functions
    // =========================

    /// @inheritdoc IExecutionLogic
    function taxedMulticall(
        bytes[] calldata data
    ) external payable override onlyOwner {
        uint256 gasUsed = gasleft();

        _multicall(data);

        uint256 l1GasFees = ARB_GAS_ORACLE.getCurrentTxL1GasFees();

        unchecked {
            gasUsed = (gasUsed - gasleft()) * tx.gasprice;
        }

        _transferDittoFee(gasUsed, l1GasFees, true);
    }
}

