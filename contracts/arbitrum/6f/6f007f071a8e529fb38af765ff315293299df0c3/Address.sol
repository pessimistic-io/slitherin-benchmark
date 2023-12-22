// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

library Address {
    error Address__SendFailed();
    error Address__NonContract();
    error Address__CallFailed();

    /**
     * @dev Sends the given amount of ether to the given address, forwarding all available gas and reverting on errors.
     * @param target The address to send ether to.
     * @param value The amount of ether to send.
     */
    function sendValue(address target, uint256 value) internal {
        (bool success,) = target.call{value: value}("");
        if (!success) revert Address__SendFailed();
    }

    /**
     * @dev Calls the target contract with the given data and bubbles up errors.
     * @param target The target contract.
     * @param data The data to call the target contract with.
     * @return The return data from the call.
     */
    function directCall(address target, bytes memory data) internal returns (bytes memory) {
        return directCallWithValue(target, data, 0);
    }

    /**
     * @dev Calls the target contract with the given data and bubbles up errors.
     * @param target The target contract.
     * @param data The data to call the target contract with.
     * @param value The amount of ether to send to the target contract.
     * @return The return data from the call.
     */
    function directCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        (bool success, bytes memory returnData) = target.call{value: value}(data);

        _catchError(target, success, returnData);

        return returnData;
    }

    /**
     * @dev Delegate calls the target contract with the given data and bubbles up errors.
     * @param target The target contract.
     * @param data The data to delegate call the target contract with.
     * @return The return data from the delegate call.
     */
    function delegateCall(address target, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returnData) = target.delegatecall(data);

        _catchError(target, success, returnData);

        return returnData;
    }

    /**
     * @dev Bubbles up errors from the target contract, target must be a contract.
     * @param target The target contract.
     * @param success The success flag from the call.
     * @param returnData The return data from the call.
     */
    function _catchError(address target, bool success, bytes memory returnData) private view {
        if (success) {
            if (returnData.length == 0 && target.code.length == 0) {
                revert Address__NonContract();
            }
        } else {
            if (returnData.length > 0) {
                assembly {
                    revert(add(32, returnData), mload(returnData))
                }
            } else {
                revert Address__CallFailed();
            }
        }
    }
}

