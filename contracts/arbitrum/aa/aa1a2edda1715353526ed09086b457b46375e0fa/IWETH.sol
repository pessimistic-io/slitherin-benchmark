pragma solidity ^0.5.4;

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
    function balanceOf(address) external view returns (uint);
    function approve(address spender, uint allowance) external returns (bool);
}

