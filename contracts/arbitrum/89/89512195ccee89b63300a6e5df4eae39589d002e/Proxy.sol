// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ProxyUtils.sol";

/// @title Proxy
/// @notice Proxy-side code for a minimal version of [OpenZeppelin's `ERC1967Proxy`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/ERC1967/ERC1967Proxy.sol).
contract Proxy is ProxyUtils {
    /// @dev Initializes the upgradeable proxy with an initial implementation specified by `_logic`.
    /// If `_data` is nonempty, it's used as data in a delegate call to `_logic`. This will typically be an encoded
    /// function call, and allows initializing the storage of the proxy like a Solidity constructor.
    constructor(address _logic) {
        _upgradeTo(_logic);
    }

    /// @dev Delegates the current call to the address returned by `_implementation()`.
    /// This function does not return to its internal call site, it will return directly to the external caller.
    function _fallback() internal {
        _delegate(_implementation());
    }

    /// @dev Fallback function that delegates calls to the address returned by `_implementation()`. Will run if no other
    /// function in the contract matches the call data.
    fallback() external payable {
        _fallback();
    }

    /// @dev Fallback function that delegates calls to the address returned by `_implementation()`. Will run if call data
    /// is empty.
    receive() external payable {
        _fallback();
    }

    /// @dev Delegates the current call to `implementation`.
    /// This function does not return to its internal call site, it will return directly to the external caller.
    function _delegate(address implementation) internal {
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}

