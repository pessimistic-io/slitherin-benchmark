// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IDepositToken {
    function initialize(address _pool) external returns (bool);
    function mint(address _to, uint256 _value) external returns (bool);
    function burn(address _from, uint256 _value) external returns (bool);
}

