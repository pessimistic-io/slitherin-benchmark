// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

interface ILockROSX {
    function lock(address _addr, uint256 _amount) external returns (bool);
    function unLock(address _addr, uint256 _amount) external returns (bool);
}
