// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

interface IBurnable {
    function burn(address _addr, uint256 _amount) external;
}

