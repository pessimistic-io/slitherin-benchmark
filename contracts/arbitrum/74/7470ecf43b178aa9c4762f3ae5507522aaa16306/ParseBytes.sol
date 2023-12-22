// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

library ParseBytes {
    function parse32BytesToBool(bytes memory data) internal pure returns (bool parsed) {
        assembly {
            parsed := mload(add(data, 32))
        }
    }
}

