// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address src, address dst, uint wad) external returns (bool);
    function withdraw(uint) external;
    function decimals() external view returns (uint8);
    function balanceOf(address account) external view returns (uint256);
}
