// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

interface ICrucibleTokenDeployer {
    function parameters()
        external
        returns (
            address,
            address,
            uint64,
            uint64,
            string memory,
            string memory
        );
}

