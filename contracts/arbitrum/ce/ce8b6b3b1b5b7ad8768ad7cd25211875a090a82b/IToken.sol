// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IToken {
    function addPair(address pair, address token) external;
    function handleFee(uint amount, address token) external;
}

