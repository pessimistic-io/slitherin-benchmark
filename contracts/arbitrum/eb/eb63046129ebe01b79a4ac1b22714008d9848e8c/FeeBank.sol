// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import {Address} from "./Address.sol";
import {IFeeBank} from "./IFeeBank.sol";

/**
 * @title Fee Bank
 * @author Trader Joe
 * @notice This contracts holds fees from the different products of the protocol.
 * The fee manager can call any contract from this contract to execute different actions.
 */
contract FeeBank is IFeeBank {
    using Address for address;

    address internal immutable _FEE_MANAGER;

    /**
     * @notice Modifier to check if the caller is the fee manager.
     */
    modifier onlyFeeManager() {
        if (msg.sender != _FEE_MANAGER) revert FeeBank__OnlyFeeManager();
        _;
    }

    /**
     * @dev Constructor that sets the fee manager address.
     * Needs to be deployed by the fee manager itself.
     */
    constructor() {
        _FEE_MANAGER = msg.sender;
    }

    /**
     * @notice Returns the fee manager address.
     * @return The fee manager address.
     */
    function getFeeManager() external view override returns (address) {
        return _FEE_MANAGER;
    }

    /**
     * @notice Delegate calls to a contract.
     * @dev Only callable by the fee manager.
     * @param target The target contract.
     * @param data The data to delegate call.
     * @return The return data from the delegate call.
     */
    function delegateCall(address target, bytes calldata data) external onlyFeeManager returns (bytes memory) {
        return target.delegateCall(data);
    }
}

