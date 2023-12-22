// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library PropagateError {
    function propagateError(
        bool success,
        bytes memory data,
        string memory errorMessage
    ) internal {
        // Forward error message from call/delegatecall
        if (!success) {
            if (data.length == 0) revert(errorMessage);
            assembly {
                revert(add(32, data), mload(data))
            }
        }
    }
}

