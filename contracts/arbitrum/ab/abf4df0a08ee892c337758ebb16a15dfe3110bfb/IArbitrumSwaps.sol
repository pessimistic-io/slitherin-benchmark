//SPDX-License-Identifier: ISC

pragma solidity ^0.8.13;

interface IArbitrumSwaps {
    function arbitrumSwaps(uint8[] calldata, bytes[] calldata) external payable;
}

