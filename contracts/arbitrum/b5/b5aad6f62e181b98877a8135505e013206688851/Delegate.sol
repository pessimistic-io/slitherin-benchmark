// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {Ownable} from "./Ownable.sol";
import {NativeReceiver} from "./NativeReceiver.sol";
import {SimpleInitializable} from "./SimpleInitializable.sol";
import {Withdrawable} from "./Withdrawable.sol";

contract Delegate is SimpleInitializable, Ownable, Withdrawable, NativeReceiver {
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

