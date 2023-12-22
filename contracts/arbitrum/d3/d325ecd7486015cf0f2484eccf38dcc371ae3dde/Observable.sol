//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface Observable {
    function observe(address from, address to, uint256 amount) external returns(bool);
}
