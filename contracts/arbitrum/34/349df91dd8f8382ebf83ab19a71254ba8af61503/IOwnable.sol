// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

interface IOwnable {
    function getOwner() external view returns (address);
}
