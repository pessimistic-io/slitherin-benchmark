// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract MutantPunk {
    function balanceOf(address owner) public view virtual returns (uint256);
}
