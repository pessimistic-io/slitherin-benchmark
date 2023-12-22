// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IBridgeToken {

    function withdraw(address to, uint256 amount) external returns (bool);
    function deposit(address to, uint256 amount) external returns (bool);
}
