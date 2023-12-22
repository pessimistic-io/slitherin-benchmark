// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0; 

interface ISwapper {
    function shouldRetry() external view returns (bool);
}

contract CustomResolver {
    ISwapper public immutable swapper;

    constructor(ISwapper _swapper) {
        swapper = _swapper;
    }

    function shouldRetry()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        canExec = swapper.shouldRetry();
        execPayload = "";
    }
}