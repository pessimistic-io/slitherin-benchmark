// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import {Address} from "./Address.sol";
import {IBaseComponent} from "./IBaseComponent.sol";

/**
 * @title Base Component
 * @author Trader Joe
 * @notice This contract is the base contract for all components of the protocol.
 * It contains the logic to restrict access from direct calls and delegate calls.
 * It also allow the fee manager to call any contract from this contract to execute different actions,
 * mainly to recover any tokens that are sent to this contract by mistake.
 */
abstract contract BaseComponent is IBaseComponent {
    using Address for address;

    address internal immutable _THIS = address(this);

    address internal immutable _FEE_MANAGER;

    /**
     * @notice Modifier to restrict access to delegate calls.
     */
    modifier onlyDelegateCall() {
        if (address(this) == _THIS) revert BaseComponent__OnlyDelegateCall();
        _;
    }

    /**
     * @notice Modifier to restrict access to direct calls.
     */
    modifier onlyDirectCall() {
        if (address(this) != _THIS) revert BaseComponent__OnlyDelegateCall();
        _;
    }

    /**
     * @notice Modifier to restrict access to the fee manager.
     */
    modifier onlyFeeManager() {
        if (msg.sender != _FEE_MANAGER) revert BaseComponent__OnlyFeeManager();
        _;
    }

    /**
     * @dev Sets the fee manager address.
     */
    constructor(address feeManager) {
        _FEE_MANAGER = feeManager;
    }

    /**
     * @notice Returns the fee manager address.
     * @return The fee manager address.
     */
    function getFeeManager() external view returns (address) {
        return _FEE_MANAGER;
    }

    /**
     * @notice Allows the fee manager to call any contract.
     * @dev Only callable by the fee manager.
     * @param target The target contract.
     * @param data The data to call.
     * @return returnData The return data from the call.
     */
    function directCall(address target, bytes calldata data)
        external
        onlyFeeManager
        onlyDirectCall
        returns (bytes memory returnData)
    {
        if (data.length == 0) {
            target.sendValue(address(this).balance);
        } else {
            returnData = target.directCall(data);
        }
    }
}

