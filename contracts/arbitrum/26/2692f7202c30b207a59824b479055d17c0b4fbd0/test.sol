// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IGLPPool {
    function pendingSenders(address user) external returns (address[] memory);
}

contract test {

    function getAddress(address glpPool, address user) external returns (address[] memory) {
        return IGLPPool(glpPool).pendingSenders(user);
    }
}