// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./KobeOwnerRegistry.sol";

abstract contract KobeOwnerChild {

    address private immutable ownerRegistry;

    constructor(address _ownerRegistry) {
        ownerRegistry = _ownerRegistry;
    }

    modifier onlyOwner {
        require (msg.sender == _getOwner(), "Only owner can call this function");
        _;
    }

    function _getOwner() internal view returns (address) {
        return KobeOwnerRegistry(ownerRegistry).owner();
    }

    function getOwner() external view returns (address) {
        return _getOwner();
    }
}
