// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "./DealsController.sol";
import "./FeeSettingsDecorator.sol";

contract GigaSwap is DealsController, FeeSettingsDecorator {
    constructor(address feeSettingsAddress)
        FeeSettingsDecorator(feeSettingsAddress)
    {}
}

