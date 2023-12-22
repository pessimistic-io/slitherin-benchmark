// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IL2 {

    function mintToTreasury(uint256 amount) external;

    function burn(uint256 amount) external;

}

