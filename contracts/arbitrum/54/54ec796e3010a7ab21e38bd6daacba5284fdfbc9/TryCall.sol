// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library TryCall {
    function call(address _destination, bytes memory _message) internal {
        (bool success, bytes memory _returnData) = _destination.call(_message);
        if (success) {
            return;
        }
        // If the _res length is less than 68, then the transaction failed silently (without a revert message)
        if (_returnData.length < 68) revert('Transaction reverted silently');

        assembly {
        // Slice the sighash.
            _returnData := add(_returnData, 0x04)
        }
        revert(abi.decode(_returnData, (string))); // All that remains is the revert string
    }
}
