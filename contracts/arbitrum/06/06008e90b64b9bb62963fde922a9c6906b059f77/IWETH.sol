// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IWETH {
    function balanceOf(address addr) external view returns (uint256);
    function allowance(address from, address to) external view returns (uint256);
    function deposit() external payable;
    function withdraw(uint wad) external;

    function totalSupply() external view returns (uint);

    function approve(address guy, uint wad) external returns (bool);

    function transfer(address dst, uint wad) external returns (bool);

    function transferFrom(address src, address dst, uint wad)
        external
        returns (bool);
}
