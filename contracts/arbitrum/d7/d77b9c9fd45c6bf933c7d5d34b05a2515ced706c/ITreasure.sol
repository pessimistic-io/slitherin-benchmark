//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
interface ITreasure {
    function burn(address _account, uint256 _id, uint256 _value) external;
}

