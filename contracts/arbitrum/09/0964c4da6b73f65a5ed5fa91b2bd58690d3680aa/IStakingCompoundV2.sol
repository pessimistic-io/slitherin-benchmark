// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

interface IStakingCompoundV2 {
    function getAddrStaking(address _addr) external returns (uint256);
    function depositRw(address addr, uint256 _amount, uint256 _index) external returns (bool);
}
