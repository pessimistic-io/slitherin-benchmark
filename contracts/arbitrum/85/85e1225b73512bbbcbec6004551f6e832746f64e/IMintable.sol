// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

// Horse.Link oracle interface
interface IMintable {
    function mintTo(address to, uint256 amount) external;
}

