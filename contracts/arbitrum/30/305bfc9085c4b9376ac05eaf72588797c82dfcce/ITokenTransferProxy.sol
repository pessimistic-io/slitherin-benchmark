// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface ITokenTransferProxy {
    function transferFrom(address, address, address, uint256)
        external
        returns (bool);
}

