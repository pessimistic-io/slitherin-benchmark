pragma solidity ^0.8.0;

interface IWeth {
    function deposit() external payable;
    function withdraw(uint wad) external;
    function transfer(address dst, uint wad) external returns (bool);
    function balanceOf(address) external returns (uint);
}
