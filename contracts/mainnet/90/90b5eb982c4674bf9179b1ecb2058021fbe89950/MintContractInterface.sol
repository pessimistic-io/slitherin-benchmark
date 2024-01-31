// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

interface MintContractInterface {
    function mintAfterBurning(address _caller, uint256 _amount) external;
}

