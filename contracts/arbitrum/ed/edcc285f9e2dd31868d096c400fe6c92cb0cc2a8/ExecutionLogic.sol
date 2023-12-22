// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC721Receiver} from "./IERC721Receiver.sol";

import {DittoFeeBase, IProtocolFees} from "./DittoFeeBase.sol";
import {BaseContract} from "./BaseContract.sol";
import {MulticallBase} from "./MulticallBase.sol";

import {IExecutionLogic} from "./IExecutionLogic.sol";

/// @title ExecutionLogic
/// @notice This contract holds the logic for executing any transactions
/// to the target contract or batch txs in multicall
contract ExecutionLogic is
    IExecutionLogic,
    BaseContract,
    IERC721Receiver,
    MulticallBase,
    DittoFeeBase
{
    // =========================
    // Constructor
    // =========================

    constructor(IProtocolFees protocolFees) DittoFeeBase(protocolFees) {}

    // =========================
    // Main functions
    // =========================

    /// @notice Allows a contract to handle receiving ERC721 tokens.
    /// @dev Returns the magic value to signal a successful receipt.
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /// @inheritdoc IExecutionLogic
    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external payable onlyVaultItself returns (bytes memory) {
        if (target == address(this)) {
            revert ExecutionLogic_ExecuteTargetCannotBeAddressThis();
        }

        // If `vault` does not have enough value on baalnce -> revert
        (bool success, bytes memory returnData) = target.call{value: value}(
            data
        );

        // If unsuccess occured -> revert with target address and calldata for it
        // to make it easier to understand the cause of the error
        if (!success) {
            revert ExecutionLogic_ExecuteCallReverted(target, data);
        }

        emit DittoExecute(target, data);

        return returnData;
    }

    /// @inheritdoc IExecutionLogic
    function multicall(
        bytes[] calldata data
    ) external payable onlyOwnerOrVaultItself {
        _multicall(data);
    }

    /// @inheritdoc IExecutionLogic
    function taxedMulticall(
        bytes[] calldata data
    ) external payable virtual onlyOwner {
        uint256 gasUsed = gasleft();

        _multicall(data);

        unchecked {
            gasUsed -= gasleft();
        }

        _transferDittoFee(gasUsed, 0, true);
    }
}

