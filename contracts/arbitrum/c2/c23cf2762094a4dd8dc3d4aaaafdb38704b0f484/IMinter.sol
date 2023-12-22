// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IMinter {
    function mint(address _gauge) external;
}
