// SPDX-License-Identifier: MIT LICENSE

pragma solidity >0.8.0;
import "./IHideNSeek.sol";
import "./IPABStake.sol";

contract BOOBase {
    IHideNSeek public hidenseek;
    IPABStake public pabstake;

    uint256 _cap;

    // a mapping from an address to whether or not it can mint / burn
    mapping(address => bool) controllers;

    mapping(address => uint256) fundingAllocation;
    address[] fundingAddresses;
}

