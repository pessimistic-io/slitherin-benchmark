// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {Address} from "./Address.sol";

/// @notice Writes notes to event log for function calls.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/AnnotatingMulticall.sol)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Multicall.sol)
abstract contract AnnotatingMulticall {
    event Multicall(bytes[] results, string[] notes);

    /**
     * @dev Receives and executes a batch of function calls on this contract.
     */
    function multicall(bytes[] calldata data, string[] calldata notes) external returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            // Assumes delegatecall to address(this) is safe for a proxy
            results[i] = Address.functionDelegateCall(address(this), data[i]);
        }
        emit Multicall(results, notes);
    }
}

