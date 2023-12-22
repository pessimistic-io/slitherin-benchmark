// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IDEI {
    function mint(address to, uint256 amount) external;

    function burn(uint256 amount) external;
}

