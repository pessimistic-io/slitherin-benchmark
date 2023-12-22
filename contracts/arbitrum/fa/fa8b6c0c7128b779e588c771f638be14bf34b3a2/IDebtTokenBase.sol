// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

interface IDebtTokenBase{
    function approveDelegation(address delegatee, uint256 amount) external;
}
