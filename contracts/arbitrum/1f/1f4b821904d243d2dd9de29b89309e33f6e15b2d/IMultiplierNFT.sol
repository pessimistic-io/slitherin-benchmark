//!UNUSED INTERFACE

pragma solidity ^0.8.14;

// SPDX-License-Identifier: MIT

interface IMultiplierNFT {

    function mint(address _to, uint _multiplier) external;
    function multipliers(uint) external view returns(uint);
}
