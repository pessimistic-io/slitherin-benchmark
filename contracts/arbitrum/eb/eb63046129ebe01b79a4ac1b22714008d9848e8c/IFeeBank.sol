// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

interface IFeeBank {
    error FeeBank__NonContract();
    error FeeBank__CallFailed();
    error FeeBank__OnlyFeeManager();

    function getFeeManager() external view returns (address);

    function delegateCall(address target, bytes calldata data) external returns (bytes memory);
}

