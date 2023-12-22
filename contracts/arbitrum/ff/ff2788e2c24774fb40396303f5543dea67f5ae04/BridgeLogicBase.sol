// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AccessControlLib} from "./AccessControlLib.sol";
import {BaseContract} from "./BaseContract.sol";
import {MulticallBase} from "./MulticallBase.sol";

/// @title BridgeLogicBase
/// @notice This contract provides the base logic for bridging functionalities.
contract BridgeLogicBase is BaseContract, MulticallBase {
    // =========================
    // Constructor
    // =========================

    /// @dev Address to receive cross-chain messages for validation and transmitting.
    address internal immutable dittoReceiver;

    /// @notice Initializes the contract with the ditto receiver address.
    /// @param _dittoReceiver The address of the ditto bridge receiver.
    constructor(address _dittoReceiver) {
        dittoReceiver = _dittoReceiver;
    }

    // =========================
    // Helper functions
    // =========================

    /// @dev Validates the caller of a bridge function.
    /// @dev Retrieves the owner and vault ID from the AccessControlLib and ensures the caller is authorized.
    /// This is a view function that uses low-level calls for error handling.
    /// @param errorSelector The function selector to return in case of an unauthorized call.
    /// @return owner The address of the owner.
    /// @return vaultId The vault ID associated with the creator.
    function _validateBridgeCall(
        bytes4 errorSelector
    ) internal view returns (address owner, uint16 vaultId) {
        owner = AccessControlLib.getOwner();
        address creator;
        (creator, vaultId) = AccessControlLib.getCreatorAndId();

        if (creator != owner || !AccessControlLib.crossChainLogicIsActive()) {
            assembly ("memory-safe") {
                mstore(0, errorSelector)
                revert(0, 0x04)
            }
        }
    }
}

