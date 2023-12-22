// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

abstract contract IGLPPool {
    function pendingSenders(address user) external view virtual returns (address[] memory);
}

contract test {

    function getAddress(address glpPool, address user) external view returns (address[] memory) {
        return IGLPPool(glpPool).pendingSenders(user);
    }
}