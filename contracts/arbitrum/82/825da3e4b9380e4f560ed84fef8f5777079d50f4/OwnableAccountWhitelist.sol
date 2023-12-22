// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.16;

import {Ownable} from "./Ownable.sol";
import {EnumerableSet} from "./EnumerableSet.sol";

import {SimpleInitializable} from "./SimpleInitializable.sol";

import {IOwnableAccountWhitelist} from "./IOwnableAccountWhitelist.sol";

contract OwnableAccountWhitelist is IOwnableAccountWhitelist, Ownable, SimpleInitializable {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _accounts;

    constructor() {
        _initializeWithSender();
    }

    function getWhitelistedAccounts() external view returns (address[] memory) {
        return _accounts.values();
    }

    function isAccountWhitelisted(address account_) external view returns (bool) {
        return _accounts.contains(account_);
    }

    function addAccountToWhitelist(address account_) external whenInitialized onlyOwner {
        require(_accounts.add(account_), "WL: account already included");
        emit AccountAdded(account_);
    }

    function removeAccountFromWhitelist(address account_) external whenInitialized onlyOwner {
        require(_accounts.remove(account_), "WL: account already excluded");
        emit AccountRemoved(account_);
    }

    function _initialize() internal override {
        _transferOwnership(initializer());
    }
}

