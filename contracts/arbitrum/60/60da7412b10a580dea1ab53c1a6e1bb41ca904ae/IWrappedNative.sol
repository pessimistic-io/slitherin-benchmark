pragma solidity 0.8.17;

interface IWrappedNative {
    function deposit() external payable;

    function withdraw(uint _amount) external;

    function balanceOf(address _user) external;

    function transfer(address dst, uint wad) external;

    function transferFrom(address src, address dst, uint wad) external;
}

