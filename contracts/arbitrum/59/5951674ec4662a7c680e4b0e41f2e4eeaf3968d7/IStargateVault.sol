// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0; 

interface IStargateVault {
    function deposit() external payable;
    function token() external view returns (address);
}

