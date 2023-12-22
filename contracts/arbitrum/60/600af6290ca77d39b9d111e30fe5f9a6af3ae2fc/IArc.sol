// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface IArc {
    function approve(address _spender, uint _value) external returns (bool);
    function burn(uint amount) external;
    function mint(address account, uint amount) external;
    function transfer(address, uint) external returns (bool);
    function transferFrom(address _from, address _to, uint _value) external;
}
