// SPDX-License-Identifier: MIT LICENSE
pragma solidity >0.8.0;

import "./IPeekABoo.sol";

contract StakeManagerBase {
    address[] services;
    mapping(address => uint256) serviceAddressToIndex;
    mapping(uint256 => address) public tokenIdToStakeService;
    mapping(uint256 => address) public tokenIdToOwner;
    mapping(address => string) public stakeServiceToServiceName;

    mapping(uint256 => uint256) public tokenIdToEnergy;
    mapping(uint256 => uint256) public tokenIdToClaimtime;

    IPeekABoo peekaboo;
    mapping(address => uint256[]) public ownerToTokens;
}

