// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.7;

/// IWETH9.sol from https://arbiscan.io/address/0x8b194beae1d3e0788a1a35173978001acdfba668#code
interface IWETH {
    function deposit() external payable;

    function withdraw(uint256 _amount) external;
}

