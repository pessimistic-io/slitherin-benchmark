//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ISupplies {
    function burn(address _from, uint256 _id, uint256 _amount) external;
}

