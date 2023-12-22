// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IChamSLIZ {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function deposit(uint256 _amount) external;
    function notifyFeeAmounts(uint256 _amount) external;
}

