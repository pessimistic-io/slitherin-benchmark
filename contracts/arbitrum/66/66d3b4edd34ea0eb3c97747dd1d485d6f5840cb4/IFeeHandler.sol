// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFeeHandler {
    function notifyFees(address token, uint amount) external;
}

