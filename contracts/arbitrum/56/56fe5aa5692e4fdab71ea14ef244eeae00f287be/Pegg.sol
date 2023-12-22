// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import {ERC20} from "./ERC20.sol";
import {ERC20Permit} from "./draft-ERC20Permit.sol";
import {ERC20Votes} from "./ERC20Votes.sol";

contract Pegg is ERC20, ERC20Permit("Pegged Finance"), ERC20Votes {
    constructor(uint256 initalSuply) ERC20("Pegged Finance", "PEGG") {
        _mint(msg.sender, initalSuply);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._mint(to, amount);
    }

    function _burn(
        address account,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }
}

