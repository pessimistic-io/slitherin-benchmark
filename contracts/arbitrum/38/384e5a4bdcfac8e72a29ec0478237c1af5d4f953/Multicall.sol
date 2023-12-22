// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

contract Multicall {
    /// @notice Multiple calls on proxy functions
    /// @param _data The destination address
    function multicall(bytes[] calldata _data) public payable {
        for (uint256 i = 0; i < _data.length;) {
            (bool success, bytes memory result) = address(this).delegatecall(_data[i]);

            if (!success) {
                if (result.length < 68) revert();

                assembly {
                    result := add(result, 0x04)
                }

                revert(abi.decode(result, (string)));
            }

            unchecked {
                ++i;
            }
        }
    }
}

