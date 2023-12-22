// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import "./IDiagonalRegistryProxy.sol";

import { Initializable } from "./Initializable.sol";

contract DiagonalRegistryProxy is Initializable, IDiagonalRegistryProxy {
    /*******************************
     * Errors *
     *******************************/

    error DiagonalRegistryProxyInitializationFailed();
    error NotContract();
    error SendingEthUnsupported();

    /*******************************
     * Constants *
     *******************************/

    // EIP 1967 BEACON SLOT
    // bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1)
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /*******************************
     * Functions start *
     *******************************/

    /// @inheritdoc IDiagonalRegistryProxy
    function initializeProxy(address implementation, bytes calldata data) external override initializer {
        assert(_IMPLEMENTATION_SLOT == bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1));

        if (data.length == 0) revert DiagonalRegistryProxyInitializationFailed();

        _setImplementation(implementation);

        _safeInitDelegateCall(implementation, data);
    }

    // solhint-disable-next-line no-complex-fallback
    fallback() external payable {
        address implementation = _implementation();

        // solhint-disable-next-line no-inline-assembly
        assembly {
            calldatacopy(0, 0, calldatasize())

            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

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

    receive() external payable {
        revert SendingEthUnsupported();
    }

    function _safeInitDelegateCall(address implementation, bytes memory data) private {
        // NOTE: This method assumes "initialize()", do not return values.
        // Handling return values would involve extra checks.

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = implementation.delegatecall(data);

        if (!success) {
            if (returndata.length > 0) {
                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            }
            revert DiagonalRegistryProxyInitializationFailed();
        }
    }

    function _setImplementation(address newImplementation) private {
        if (newImplementation.code.length == 0) revert NotContract();
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(_IMPLEMENTATION_SLOT, newImplementation)
        }
    }

    function _implementation() private view returns (address implementation) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            implementation := sload(_IMPLEMENTATION_SLOT)
        }
    }
}

