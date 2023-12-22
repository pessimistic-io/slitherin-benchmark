// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

interface IVester {
    function deposit(uint256 _amount) external;
    function claim() external returns (uint256);
    function claimable(address account) external view returns (uint256);
}

