// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "./NonfungibleTokenPositionDescriptor.sol";

/// @title Tick Lens contract
contract TestNonfungibleTokenPositionDescriptor is NonfungibleTokenPositionDescriptor {
    constructor(address _WETH9, bytes32 _nativeCurrencyLabelBytes) NonfungibleTokenPositionDescriptor() {
        WETH9 = _WETH9;
        nativeCurrencyLabelBytes = _nativeCurrencyLabelBytes;
    }
}

