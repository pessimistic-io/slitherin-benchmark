// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.20;

import "./UUPSUpgradeable.sol";

contract InitialProxyImpl is UUPSUpgradeable {
    error NotOwner(address owner, address caller);

    address public immutable owner;
    // It doesnt matter that's only on the storage of the contract, as it's only used for identification purposes
    string public name;

    constructor(address _owner, string memory _name) {
        owner = _owner;
        name = _name;
    }

    function _authorizeUpgrade(address) internal virtual override {
        if (msg.sender != owner) revert NotOwner(owner, msg.sender);
    }
}

