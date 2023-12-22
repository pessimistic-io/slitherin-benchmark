// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {SSTORE2} from "./SSTORE2.sol";
import {BinarySearch} from "./BinarySearch.sol";

import {IVault} from "./IVault.sol";

/// @title Vault
/// @notice This contract serves as a proxy for dynamic function execution.
/// @dev It maps function selectors to their corresponding logic contracts.
contract Vault is IVault {
    //-----------------------------------------------------------------------//
    // function selectors and logic addresses are stored as bytes data:      //
    // selector . address                                                    //
    // sample:                                                               //
    // 0xaaaaaaaa <- selector                                                //
    // 0xffffffffffffffffffffffffffffffffffffffff <- address                 //
    // 0xaaaaaaaaffffffffffffffffffffffffffffffffffffffff <- one element     //
    //-----------------------------------------------------------------------//

    /// @dev Address where logic and selector bytes are stored using SSTORE2.
    address private immutable logicsAndSelectorsAddress;

    /// @inheritdoc IVault
    address public immutable getImplementationAddress;

    /// @notice Initializes a new Vault contract.
    /// @param selectors An array of bytes4 function selectors that correspond
    ///        to the logic addresses.
    /// @param logicAddresses An array of addresses, each being the implementation
    ///        address for the corresponding selector.
    ///
    /// @dev Sets up the logic and selectors for the Vault contract,
    /// ensuring that the passed selectors are in order and there are no repetitions.
    /// @dev Ensures that the sizes of selectors and logic addresses match.
    /// @dev The constructor uses inline assembly to optimize memory operations and
    /// stores the combined logic and selectors in a specified storage location.
    ///
    /// Requirements:
    /// - `selectors` and `logicAddresses` arrays must have the same length.
    /// - `selectors` array should be sorted in increasing order and have no repeated elements.
    ///
    /// Errors:
    /// - Thrown `Vault_InvalidConstructorData` error if data validation fails.
    constructor(bytes4[] memory selectors, address[] memory logicAddresses) {
        uint256 selectorsLength = selectors.length;

        if (selectorsLength != logicAddresses.length) {
            revert Vault_InvalidConstructorData();
        }

        if (selectorsLength > 0) {
            // check that the selectors are sorted and there's no repeating
            for (uint256 i; i < selectorsLength - 1; ) {
                if (selectors[i] >= selectors[i + 1]) {
                    revert Vault_InvalidConstructorData();
                }

                unchecked {
                    ++i;
                }
            }
        }

        bytes memory logicsAndSelectors = new bytes(selectorsLength * 24);

        assembly ("memory-safe") {
            let logicAndSelectorValue
            // counter
            let i
            // offset in memory to the beginning of selectors array values
            let selectorsOffset := add(selectors, 32)
            // offset in memory to beginning of logicsAddresses array values
            let logicsAddressesOffset := add(logicAddresses, 32)
            // offset in memory to beginning of logicsAndSelectorsOffset bytes
            let logicsAndSelectorsOffset := add(logicsAndSelectors, 32)

            for {

            } lt(i, selectorsLength) {
                // post actions
                i := add(i, 1)
                selectorsOffset := add(selectorsOffset, 32)
                logicsAddressesOffset := add(logicsAddressesOffset, 32)
                logicsAndSelectorsOffset := add(logicsAndSelectorsOffset, 24)
            } {
                // value creation:
                // 0xaaaaaaaaffffffffffffffffffffffffffffffffffffffff0000000000000000
                logicAndSelectorValue := or(
                    mload(selectorsOffset),
                    shl(64, mload(logicsAddressesOffset))
                )
                // store the value in the logicsAndSelectors byte array
                mstore(logicsAndSelectorsOffset, logicAndSelectorValue)
            }
        }

        logicsAndSelectorsAddress = SSTORE2.write(logicsAndSelectors);
        getImplementationAddress = address(this);
    }

    // =========================
    // Main function
    // =========================

    /// @notice Fallback function to execute logic associated with incoming function selectors.
    /// @dev If a logic for the incoming selector is found, it delegates the call to that logic.
    fallback() external payable {
        address logic = _getAddress(msg.sig);

        if (logic == address(0)) {
            revert Vault_FunctionDoesNotExist();
        }

        assembly ("memory-safe") {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), logic, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    /// @notice Function to accept Native Currency sent to the contract.
    receive() external payable {}

    // =======================
    // Internal functions
    // =======================

    /// @dev Searches for the logic address associated with a function `selector`.
    /// @dev Uses binary search to find the logic address in logicsAndSelectors bytes.
    /// @param selector The function selector.
    /// @return logic The address of the logic contract.
    function _getAddress(
        bytes4 selector
    ) internal view returns (address logic) {
        bytes memory logicsAndSelectors = SSTORE2.read(
            logicsAndSelectorsAddress
        );

        if (logicsAndSelectors.length < 24) {
            revert Vault_FunctionDoesNotExist();
        }

        return BinarySearch.binarySearch(selector, logicsAndSelectors);
    }
}

