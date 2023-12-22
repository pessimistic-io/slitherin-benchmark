// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {GelatoRelayContext} from "./GelatoRelayContext.sol";
import {ERC20} from "./ERC20.sol";

contract GelatoERC20 is ERC20, GelatoRelayContext {
    constructor(address initialHolder)
        ERC20("DemoERC20", "DTK")
    {
        _mint(initialHolder, 10 ** 10);
    }

    function _transfer(address from, address to, uint256 amount)
        internal
        virtual
        override
        onlyGelatoRelay
    {
        _transferRelayFee();
        super._transfer(from, to, amount);
    }
}

