// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

interface IMintable {
    function mint(address _addr, uint256 _amount) external;
}

