// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IFixedSupplyERC20 {
    function initialize(
        address _owner,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _totalSupply,
        address _minter
    ) external;
}

