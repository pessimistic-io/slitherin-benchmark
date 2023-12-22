// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./PTokenStorage.sol";
import "./CommonModifiers.sol";

abstract contract PTokenModifiers is PTokenStorage, CommonModifiers {

    modifier onlyMid() {
        if (msg.sender != address(middleLayer)) {
            revert OnlyMiddleLayer();
        }
        _;
    }

    modifier onlyRequestController() {
        if (msg.sender != requestController) revert OnlyRequestController();
        _;
    }

    modifier sanityDeposit(uint256 amount, address user) {
        if (amount == 0) revert ExpectedDepositAmount();
        if (user == address(0)) revert AddressExpected();
        if (isFrozen) revert MarketIsFrozen(address(this));
        if (isdeprecated) revert MarketIsdeprecated(address(this));

        _;
    }
}

