pragma solidity ^0.8.0;

interface IMintableERC20 {
    function mint(address account, uint amount) external;
    function burn(address account, uint amount) external;
}

