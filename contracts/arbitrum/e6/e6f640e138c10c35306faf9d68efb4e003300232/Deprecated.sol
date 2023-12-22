//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract Deprecated {
    fallback() external payable {
        revert("Contract Deprecated");
    }
}