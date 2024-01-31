// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.16;

import {Ownable} from "./Ownable.sol";

import {TokenHelper} from "./TokenHelper.sol";
import {NativeReceiver} from "./NativeReceiver.sol";

import {SimpleInitializable} from "./SimpleInitializable.sol";

import {IWithdrawable} from "./IWithdrawable.sol";
import {Withdrawable, Withdraw} from "./Withdrawable.sol";

import {IDelegate} from "./IDelegate.sol";

contract Delegate is IDelegate, SimpleInitializable, Ownable, Withdrawable, NativeReceiver {
    constructor() {
        _initializeWithSender();
    }

    function _initialize() internal override {
        _transferOwnership(initializer());
    }

    function setOwner(address newOwner_) external whenInitialized onlyInitializer {
        _transferOwnership(newOwner_);
    }

    function _checkWithdraw() internal view override {
        _ensureInitialized();
        _checkOwner();
    }
}

