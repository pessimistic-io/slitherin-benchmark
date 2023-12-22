// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IBridge {
    function swap(
        address,
        address,
        address,
        uint256,
        uint256,
        uint32,
        bytes calldata
    ) external;

    function release(address, uint256, address) external;
}

