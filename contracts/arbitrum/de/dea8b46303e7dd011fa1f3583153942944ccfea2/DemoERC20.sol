// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Context} from "./Context.sol";
import {ERC20} from "./ERC20.sol";
import {ERC2771Context} from "./ERC2771Context.sol";

contract DemoERC20 is ERC20, ERC2771Context {
    constructor(address initialHolder, address forwarder)
        ERC20("DemoERC20", "DTK")
        ERC2771Context(forwarder)
    {
        _mint(initialHolder, 10 ** 10);
    }

    function _msgSender() internal view virtual override(Context, ERC2771Context) returns (address sender) {
        return ERC2771Context._msgSender();
    }

    function _msgData() internal view virtual override(Context, ERC2771Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }
}

